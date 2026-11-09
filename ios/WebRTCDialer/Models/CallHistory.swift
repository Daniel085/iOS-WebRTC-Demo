//
//  CallHistory.swift
//  WebRTCDialer
//
//  Local call history (the Recents tab), including each call's transcript
//  and AI summary. Stored as JSON in Application Support on this device only.
//

import Foundation
import Combine
import SwiftUI

/// One line of a call transcript.
struct TranscriptLine: Codable, Identifiable, Equatable, Sendable {
    enum Speaker: String, Codable, Sendable {
        case me
        case peer
    }

    let id: String
    let speaker: Speaker
    var text: String
    var isFinal: Bool
    let startedAt: Date
}

/// AI summary of a transcribed call.
struct CallSummary: Codable, Equatable, Sendable {
    var summary: String
    var actionItems: [String]
    var keyPoints: [String]
    var generatedAt: Date
}

struct CallRecord: Codable, Identifiable, Equatable {
    enum Outcome: String, Codable {
        case completed
        case missed
        case declined
        case noAnswer
        case failed
    }

    enum SummaryStatus: Equatable, Codable {
        case none
        case pending
        case ready
        case failed(String)
    }

    let id: UUID
    let callId: String
    let phoneNumber: String
    let isOutgoing: Bool
    let isVideo: Bool
    let startedAt: Date
    var duration: TimeInterval
    var outcome: Outcome
    var transcript: [TranscriptLine]
    var summary: CallSummary?
    var summaryStatus: SummaryStatus

    var hasTranscript: Bool { !transcript.isEmpty }
    var isMissed: Bool { outcome == .missed }
}

@MainActor
final class CallHistoryStore: ObservableObject {
    static let shared = CallHistoryStore()

    /// Newest first.
    @Published private(set) var records: [CallRecord] = []

    private let fileURL: URL
    private let maxRecords = 200

    private init() {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("call-history.json")
        load()
    }

    func record(id: UUID) -> CallRecord? {
        records.first { $0.id == id }
    }

    func add(_ record: CallRecord) {
        records.removeAll { $0.id == record.id }
        records.insert(record, at: 0)
        if records.count > maxRecords { records.removeLast(records.count - maxRecords) }
        save()
    }

    func update(id: UUID, _ change: (inout CallRecord) -> Void) {
        guard let index = records.firstIndex(where: { $0.id == id }) else { return }
        change(&records[index])
        save()
    }

    func delete(at offsets: IndexSet) {
        records.remove(atOffsets: offsets)
        save()
    }

    func deleteTranscript(id: UUID) {
        update(id: id) {
            $0.transcript = []
            $0.summary = nil
            $0.summaryStatus = .none
        }
    }

    // MARK: Summaries

    /// Ask the backend to summarize a transcribed call and store the result.
    func requestSummary(id: UUID) {
        guard let record = record(id: id), record.hasTranscript else { return }
        update(id: id) { $0.summaryStatus = .pending }
        Task {
            do {
                let summary = try await CallSummaryService.summarize(callId: record.callId, transcript: record.transcript)
                update(id: id) {
                    $0.summary = summary
                    $0.summaryStatus = .ready
                }
            } catch {
                print("📝 [History] Summary failed: \(error.localizedDescription)")
                update(id: id) { $0.summaryStatus = .failed(error.localizedDescription) }
            }
        }
    }

    // MARK: Persistence

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        do {
            records = try JSONDecoder.history.decode([CallRecord].self, from: data)
            // A summary request can't still be running after a relaunch.
            for index in records.indices where records[index].summaryStatus == .pending {
                records[index].summaryStatus = .failed("Interrupted")
            }
        } catch {
            print("📝 [History] Could not read history: \(error.localizedDescription)")
        }
    }

    private func save() {
        do {
            let data = try JSONEncoder.history.encode(records)
            try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
        } catch {
            print("📝 [History] Could not save history: \(error.localizedDescription)")
        }
    }
}

private extension JSONEncoder {
    static var history: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension JSONDecoder {
    static var history: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

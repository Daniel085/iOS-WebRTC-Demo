//
//  RecentsView.swift
//  WebRTCDialer
//
//  Call history from CallHistoryStore. Transcribed calls open a detail screen
//  with the AI summary, action items and the full transcript.
//

import SwiftUI

struct RecentsView: View {
    @ObservedObject private var history = CallHistoryStore.shared

    var body: some View {
        NavigationStack {
            Group {
                if history.records.isEmpty {
                    ContentUnavailableView(
                        "No Recent Calls",
                        systemImage: "phone.circle",
                        description: Text("Your call history will appear here")
                    )
                } else {
                    List {
                        ForEach(history.records) { record in
                            NavigationLink(value: record.id) {
                                RecentCallRow(record: record)
                            }
                        }
                        .onDelete { history.delete(at: $0) }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Recents")
            .navigationDestination(for: UUID.self) { id in
                CallDetailView(recordId: id)
            }
        }
    }
}

struct RecentCallRow: View {
    let record: CallRecord

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: record.isVideo ? "video.fill" : "phone.fill")
                .foregroundColor(record.isMissed ? .red : .gray)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text(record.phoneNumber)
                    .font(.body)
                    .foregroundColor(record.isMissed ? .red : .primary)

                HStack(spacing: 5) {
                    Image(systemName: record.isOutgoing ? "phone.arrow.up.right" : "phone.arrow.down.left")
                    Text(record.outcomeText)
                    if record.outcome == .completed {
                        Text("·")
                        Text(record.durationText)
                    }
                }
                .font(.caption)
                .foregroundColor(.secondary)

                if let summary = record.summary?.summary {
                    Text(summary)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(record.startedAt, format: .relative(presentation: .named))
                    .font(.caption)
                    .foregroundColor(.secondary)
                if record.hasTranscript {
                    Image(systemName: "text.bubble")
                        .foregroundColor(.blue)
                        .accessibilityLabel("Transcribed")
                }
            }
        }
        .padding(.vertical, 4)
    }
}

struct CallDetailView: View {
    let recordId: UUID
    @ObservedObject private var history = CallHistoryStore.shared
    @State private var confirmDelete = false

    var body: some View {
        if let record = history.record(id: recordId) {
            List {
                Section {
                    LabeledContent("Direction", value: record.isOutgoing ? "Outgoing" : "Incoming")
                    LabeledContent("Result", value: record.outcome == .completed ? "Answered" : record.outcomeText)
                    LabeledContent("When", value: record.startedAt.formatted(date: .abbreviated, time: .shortened))
                    if record.outcome == .completed {
                        LabeledContent("Duration", value: record.durationText)
                    }
                    Button {
                        CallManager.shared.startCall(to: record.phoneNumber, hasVideo: false)
                    } label: {
                        Label("Call back", systemImage: "phone.fill")
                    }
                }

                if record.hasTranscript {
                    summarySection(record)

                    Section("Transcript") {
                        ForEach(record.transcript) { line in
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(line.speaker == .me ? "You" : record.phoneNumber)
                                        .font(.caption.weight(.semibold))
                                    Spacer()
                                    Text(line.startedAt, format: .dateTime.hour().minute().second())
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                .foregroundColor(line.speaker == .me ? .blue : .secondary)
                                Text(line.text)
                                    .textSelection(.enabled)
                            }
                            .padding(.vertical, 2)
                        }
                    }

                    Section {
                        Button("Delete Transcript and Summary", role: .destructive) {
                            confirmDelete = true
                        }
                    } footer: {
                        Text("Transcripts are stored only on this iPhone. The server keeps no copy after making the summary.")
                    }
                }
            }
            .navigationTitle(record.phoneNumber)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if record.hasTranscript {
                    ShareLink(item: record.shareText) {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
            .confirmationDialog("Delete this call's transcript and summary?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) { history.deleteTranscript(id: recordId) }
            } message: {
                Text("This can't be undone.")
            }
        } else {
            ContentUnavailableView("Call Not Found", systemImage: "phone.badge.exclamationmark")
        }
    }

    @ViewBuilder
    private func summarySection(_ record: CallRecord) -> some View {
        Section("Summary") {
            switch record.summaryStatus {
            case .pending:
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Summarizing…").foregroundColor(.secondary)
                }
            case .failed(let message):
                VStack(alignment: .leading, spacing: 8) {
                    Text(message)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Button("Try Again") { history.requestSummary(id: recordId) }
                }
            case .none:
                Button("Summarize Call") { history.requestSummary(id: recordId) }
            case .ready:
                EmptyView()
            }

            if let summary = record.summary {
                Text(summary.summary)
                    .textSelection(.enabled)
            }
        }

        if let summary = record.summary, !summary.actionItems.isEmpty {
            Section("Action Items") {
                ForEach(summary.actionItems, id: \.self) { item in
                    Label(item, systemImage: "checkmark.circle")
                }
            }
        }

        if let summary = record.summary, !summary.keyPoints.isEmpty {
            Section("Key Points") {
                ForEach(summary.keyPoints, id: \.self) { point in
                    Label(point, systemImage: "smallcircle.filled.circle")
                }
            }
        }
    }
}

extension CallRecord {
    var outcomeText: String {
        switch outcome {
        case .completed: return isOutgoing ? "Outgoing" : "Incoming"
        case .missed: return "Missed"
        case .declined: return "Declined"
        case .noAnswer: return isOutgoing ? "No answer" : "Missed"
        case .failed: return "Failed"
        }
    }

    var durationText: String {
        let seconds = Int(duration.rounded())
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    /// Plain-text export for the share sheet.
    var shareText: String {
        var parts = ["Call with \(phoneNumber) — \(startedAt.formatted(date: .abbreviated, time: .shortened)) (\(durationText))"]
        if let summary {
            parts.append("Summary:\n\(summary.summary)")
            if !summary.actionItems.isEmpty {
                parts.append("Action items:\n" + summary.actionItems.map { "• \($0)" }.joined(separator: "\n"))
            }
        }
        let transcript = self.transcript
            .map { "\($0.speaker == .me ? "Me" : phoneNumber): \($0.text)" }
            .joined(separator: "\n")
        parts.append("Transcript:\n\(transcript)")
        return parts.joined(separator: "\n\n")
    }
}

#Preview {
    RecentsView()
}

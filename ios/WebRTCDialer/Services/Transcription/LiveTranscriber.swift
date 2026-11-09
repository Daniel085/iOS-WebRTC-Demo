//
//  LiveTranscriber.swift
//  WebRTCDialer
//
//  On-device speech-to-text for one speaker (this phone's microphone) using
//  the Speech framework's SpeechAnalyzer. Audio never leaves the device; only
//  the resulting text is shared with the other party.
//
//  `append(_:)` may be called from any thread (the audio tap); results are
//  delivered through `onSegment` on a background task.
//

import Foundation
import AVFoundation
import CoreMedia
import Speech

nonisolated final class LiveTranscriber: @unchecked Sendable {

    /// A run of speech. Volatile (in-progress) results keep the same `id` and
    /// are replaced by later results until one arrives with `isFinal`.
    struct Segment: Sendable {
        let id: String
        let text: String
        let isFinal: Bool
        let startedAt: Date
    }

    enum TranscriberError: LocalizedError {
        case unsupportedLocale(String)
        case noAudioFormat
        case notAuthorized

        var errorDescription: String? {
            switch self {
            case .unsupportedLocale(let id): return "On-device transcription does not support \(id)"
            case .noAudioFormat: return "No audio format is compatible with the transcriber"
            case .notAuthorized: return "Speech recognition permission was denied"
            }
        }
    }

    private let lock = NSLock()
    private var analyzer: SpeechAnalyzer?
    private var continuation: AsyncStream<AnalyzerInput>.Continuation?
    private var resultsTask: Task<Void, Never>?
    private var analyzerFormat: AVAudioFormat?
    private var converter: AVAudioConverter?
    private var firstSampleAt: Date?
    private var currentSegmentId: String?
    private var muted = false
    private(set) var modelName = ""

    // MARK: Start / stop

    /// Prepare the model (downloading it the first time) and start accepting audio.
    func start(locale: Locale = .current, contextualStrings: [String] = [], onSegment: @escaping @Sendable (Segment) -> Void) async throws {
        try await ensureAuthorized()

        let module: any SpeechModule
        let consume: @Sendable () async throws -> Void
        if SpeechTranscriber.isAvailable, let supported = await SpeechTranscriber.supportedLocale(equivalentTo: locale) {
            let transcriber = SpeechTranscriber(
                locale: supported,
                transcriptionOptions: [],
                reportingOptions: [.volatileResults, .fastResults],
                attributeOptions: [.audioTimeRange]
            )
            module = transcriber
            modelName = "SpeechTranscriber (\(supported.identifier))"
            consume = { [weak self] in
                for try await result in transcriber.results {
                    self?.emit(text: String(result.text.characters), isFinal: result.isFinal, range: result.range, to: onSegment)
                }
            }
        } else if let supported = await DictationTranscriber.supportedLocale(equivalentTo: locale) {
            let transcriber = DictationTranscriber(
                locale: supported,
                contentHints: [],
                transcriptionOptions: [.punctuation],
                reportingOptions: [.volatileResults, .frequentFinalization],
                attributeOptions: [.audioTimeRange]
            )
            module = transcriber
            modelName = "DictationTranscriber (\(supported.identifier))"
            consume = { [weak self] in
                for try await result in transcriber.results {
                    self?.emit(text: String(result.text.characters), isFinal: result.isFinal, range: result.range, to: onSegment)
                }
            }
        } else {
            throw TranscriberError.unsupportedLocale(locale.identifier)
        }

        if let request = try await AssetInventory.assetInstallationRequest(supporting: [module]) {
            log("Downloading speech model for \(modelName)")
            try await request.downloadAndInstall()
        }

        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [module]) else {
            throw TranscriberError.noAudioFormat
        }

        let (stream, continuation) = AsyncStream.makeStream(of: AnalyzerInput.self)
        let analyzer = SpeechAnalyzer(modules: [module])
        if !contextualStrings.isEmpty {
            let context = AnalysisContext()
            context.contextualStrings[.general] = contextualStrings
            try? await analyzer.setContext(context)
        }
        try await analyzer.prepareToAnalyze(in: format)

        lock.withLock {
            self.analyzer = analyzer
            self.continuation = continuation
            self.analyzerFormat = format
            self.converter = nil
            self.firstSampleAt = nil
            self.currentSegmentId = nil
        }

        resultsTask = Task.detached { [weak self] in
            do {
                try await consume()
            } catch {
                self?.log("Results ended with error: \(error.localizedDescription)")
            }
        }

        try await analyzer.start(inputSequence: stream)
        log("Started with \(modelName), \(Int(format.sampleRate)) Hz")
    }

    /// Finish the input, wait (briefly) for the last final results, and release the model.
    func stop() async {
        let (analyzer, continuation, task) = lock.withLock { () -> (SpeechAnalyzer?, AsyncStream<AnalyzerInput>.Continuation?, Task<Void, Never>?) in
            defer {
                self.analyzer = nil
                self.continuation = nil
                self.resultsTask = nil
                self.analyzerFormat = nil
                self.converter = nil
            }
            return (self.analyzer, self.continuation, self.resultsTask)
        }
        guard let analyzer else { return }
        continuation?.finish()
        do {
            try await analyzer.finalizeAndFinishThroughEndOfInput()
        } catch {
            log("Finalize failed: \(error.localizedDescription)")
        }
        // Results normally end right after finalizing; don't hang if they don't.
        let timeout = Task.detached {
            try? await Task.sleep(for: .seconds(3))
            task?.cancel()
        }
        await task?.value
        timeout.cancel()
        log("Stopped")
    }

    // MARK: Audio input

    /// While muted, silence is fed instead of the microphone so nothing said
    /// on mute is transcribed and the timeline stays aligned with the call.
    func setMuted(_ muted: Bool) {
        lock.withLock { self.muted = muted }
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        defer { lock.unlock() }
        guard let continuation, let format = analyzerFormat, buffer.frameLength > 0 else { return }
        if firstSampleAt == nil { firstSampleAt = Date() }
        guard let converted = convert(buffer, to: format) else { return }
        if muted {
            // Zero every channel's samples, whatever the sample format.
            for buffer in UnsafeMutableAudioBufferListPointer(converted.mutableAudioBufferList) {
                if let data = buffer.mData { memset(data, 0, Int(buffer.mDataByteSize)) }
            }
        }
        continuation.yield(AnalyzerInput(buffer: converted))
    }

    /// Call with `lock` held.
    private func convert(_ buffer: AVAudioPCMBuffer, to format: AVAudioFormat) -> AVAudioPCMBuffer? {
        if converter == nil || converter?.inputFormat != buffer.format {
            converter = AVAudioConverter(from: buffer.format, to: format)
        }
        guard let converter else { return nil }
        let ratio = format.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 64
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return nil }

        var supplied = false
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            if supplied {
                status.pointee = .noDataNow
                return nil
            }
            supplied = true
            status.pointee = .haveData
            return buffer
        }
        if let error {
            log("Conversion failed: \(error.localizedDescription)")
            return nil
        }
        return output.frameLength > 0 ? output : nil
    }

    // MARK: Results

    private func emit(text: String, isFinal: Bool, range: CMTimeRange, to onSegment: @Sendable (Segment) -> Void) {
        // The dictation model sometimes emits punctuation-only results, or
        // starts a new result with the previous sentence's period.
        let leadingJunk = CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters)
        let trimmed = String(text.unicodeScalars.drop(while: { leadingJunk.contains($0) }))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let hasWords = trimmed.unicodeScalars.contains { CharacterSet.alphanumerics.contains($0) }
        let segment: Segment? = lock.withLock {
            let id = currentSegmentId ?? UUID().uuidString
            if isFinal {
                currentSegmentId = nil
            } else {
                currentSegmentId = id
            }
            guard hasWords else { return nil }
            let offset = range.start.isNumeric ? range.start.seconds : 0
            let startedAt = (firstSampleAt ?? Date()).addingTimeInterval(offset)
            return Segment(id: id, text: trimmed, isFinal: isFinal, startedAt: startedAt)
        }
        if let segment { onSegment(segment) }
    }

    // MARK: Permission

    private func ensureAuthorized() async throws {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            return
        case .notDetermined:
            let status = await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
            }
            guard status == .authorized else { throw TranscriberError.notAuthorized }
        default:
            throw TranscriberError.notAuthorized
        }
    }

    private func log(_ message: String) {
        print("📝 [Transcriber] \(message)")
    }
}

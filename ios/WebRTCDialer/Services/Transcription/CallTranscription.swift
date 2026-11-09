//
//  CallTranscription.swift
//  WebRTCDialer
//
//  Transcription for one call: the consent handshake, this phone's on-device
//  transcriber, and the merged, speaker-labelled caption list.
//
//  Consent is server-authoritative. Either person can ask; nothing is
//  transcribed or shared until the other person allows it, and either person
//  can stop it at any time. The server only relays caption text while both
//  have agreed. Each phone transcribes only its own microphone, so speaker
//  labels come for free and no call audio leaves either device.
//
//      me: request ──► server ──► peer: "wants to transcribe" (Allow / Decline)
//      peer: allow ──► server ──► both: state "active" → start transcribers
//      either: stop ─► server ──► both: state "stopped"
//

import Foundation
import AVFoundation
import Combine

@MainActor
final class CallTranscription: ObservableObject {

    enum State: Equatable {
        /// Not transcribing. The user can ask.
        case off
        /// This user asked; waiting for the other person.
        case waitingForPeer
        /// The other person asked; show the consent prompt.
        case peerRequested
        /// Both agreed; transcribers are running (or starting).
        case active
        /// The other person declined this user's request.
        case declined
    }

    @Published private(set) var state: State = .off
    /// Final and in-progress lines from both sides, oldest first.
    @Published private(set) var lines: [TranscriptLine] = []
    /// Short status text ("The other person stopped transcription", errors...).
    @Published private(set) var notice: String?
    /// True when synthesized test speech stands in for the microphone.
    @Published private(set) var usingDemoAudio = false

    /// Whether both people ever agreed during this call.
    private(set) var wasEverActive = false

    let callId: String
    let isOutgoing: Bool
    weak var signaling: SignalingClient?

    private var transcriber: LiveTranscriber?
    private var demo: DemoSpeechSource?
    private var microphoneMuted = false
    private var noticeTask: Task<Void, Never>?

    init(callId: String, isOutgoing: Bool) {
        self.callId = callId
        self.isOutgoing = isOutgoing
    }

    var isActive: Bool { state == .active }

    // MARK: User actions

    func request() {
        guard state == .off || state == .declined else { return }
        guard canTranscribeLocally else {
            show("Transcription needs the app's audio engine (turn off \"Use built-in WebRTC audio\")")
            return
        }
        state = .waitingForPeer
        signaling?.requestTranscription(callId: callId)
    }

    func accept() {
        guard state == .peerRequested else { return }
        signaling?.respondToTranscription(callId: callId, accepted: true)
    }

    func decline() {
        guard state == .peerRequested else { return }
        signaling?.respondToTranscription(callId: callId, accepted: false)
        state = .off
    }

    /// Stop transcribing for both people (or withdraw a pending request).
    func stop() {
        guard state != .off else { return }
        signaling?.stopTranscription(callId: callId)
        stopCapture()
        state = .off
    }

    /// Mute or hold: feed silence instead of the microphone.
    func setMicrophoneMuted(_ muted: Bool) {
        microphoneMuted = muted
        transcriber?.setMuted(muted)
    }

    // MARK: Server events

    /// `byYou` is true when this user performed the action behind the state.
    func handleServerState(_ newState: String, byYou: Bool) {
        switch newState {
        case "requested":
            state = byYou ? .waitingForPeer : .peerRequested
        case "active":
            state = .active
            wasEverActive = true
            show(nil)
            startCapture()
        case "declined":
            stopCapture()
            state = byYou ? .off : .declined
            if !byYou { show("The other person declined transcription") }
        case "stopped":
            stopCapture()
            state = .off
            if !byYou { show("The other person stopped transcription") }
        default:
            print("📝 [Transcription] Unknown state '\(newState)'")
        }
    }

    func handleRemoteSegment(id: String, text: String, isFinal: Bool, startedAt: Date) {
        guard state == .active else { return }
        upsert(TranscriptLine(id: id, speaker: .peer, text: text, isFinal: isFinal, startedAt: startedAt))
    }

    // MARK: Call end

    /// Stop the local transcriber, flush its last results, and return the
    /// transcript to keep. In-progress lines are kept as they last read.
    func finish() async -> [TranscriptLine] {
        let transcriber = self.transcriber
        detachAudio()
        self.transcriber = nil
        await transcriber?.stop()
        state = .off
        return lines
            .filter { !$0.text.isEmpty }
            .map { line in
                var line = line
                line.isFinal = true
                return line
            }
    }

    // MARK: Local capture

    private var canTranscribeLocally: Bool {
        DemoSpeechSource.isEnabled || WebRTCClient.usesEngineAudioDevice
    }

    private func startCapture() {
        guard transcriber == nil else { return }
        let transcriber = LiveTranscriber()
        transcriber.setMuted(microphoneMuted)
        self.transcriber = transcriber
        let callId = self.callId

        Task { [weak self] in
            do {
                try await transcriber.start { segment in
                    Task { @MainActor [weak self] in self?.handleLocalSegment(segment) }
                }
                guard let self, self.transcriber === transcriber else {
                    await transcriber.stop()
                    return
                }
                self.attachAudio(to: transcriber)
            } catch {
                print("📝 [Transcription] \(callId): could not start: \(error.localizedDescription)")
                guard let self, self.transcriber === transcriber else { return }
                self.transcriber = nil
                // The other person's captions still arrive; only this side is missing.
                self.show("Your side can't be transcribed: \(error.localizedDescription)", sticky: true)
            }
        }
    }

    private func attachAudio(to transcriber: LiveTranscriber) {
        if DemoSpeechSource.isEnabled {
            let demo = DemoSpeechSource()
            self.demo = demo
            usingDemoAudio = true
            demo.start(role: isOutgoing ? .caller : .callee) { buffer in
                transcriber.append(buffer)
            }
            print("📝 [Transcription] Using demo speech instead of the microphone")
        } else {
            EngineAudioDevice.shared.setCaptureHandler { buffer in
                transcriber.append(buffer)
            }
        }
    }

    private func detachAudio() {
        demo?.stop()
        demo = nil
        if WebRTCClient.usesEngineAudioDevice {
            EngineAudioDevice.shared.setCaptureHandler(nil)
        }
    }

    private func stopCapture() {
        detachAudio()
        if let transcriber {
            self.transcriber = nil
            Task { await transcriber.stop() }
        }
    }

    private func handleLocalSegment(_ segment: LiveTranscriber.Segment) {
        guard state == .active else { return }
        upsert(TranscriptLine(id: segment.id, speaker: .me, text: segment.text, isFinal: segment.isFinal, startedAt: segment.startedAt))
        signaling?.sendTranscriptSegment(
            callId: callId,
            id: segment.id,
            text: segment.text,
            isFinal: segment.isFinal,
            startedAt: segment.startedAt
        )
    }

    // MARK: Helpers

    private func upsert(_ line: TranscriptLine) {
        if let index = lines.firstIndex(where: { $0.id == line.id && $0.speaker == line.speaker }) {
            lines[index].text = line.text
            lines[index].isFinal = line.isFinal
        } else {
            let index = lines.firstIndex { $0.startedAt > line.startedAt } ?? lines.endIndex
            lines.insert(line, at: index)
        }
    }

    private func show(_ message: String?, sticky: Bool = false) {
        noticeTask?.cancel()
        notice = message
        guard message != nil, !sticky else { return }
        noticeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            self?.notice = nil
            if self?.state == .declined { self?.state = .off }
        }
    }
}

//
//  WebRTCClient.swift
//  WebRTCDialer
//
//  One RTCPeerConnection per call. Audio-only today; `hasVideo` is plumbed
//  through so a video track can be added later without changing callers.
//
//  Threading: the public API and the delegate callbacks are main-actor.
//  libwebrtc invokes RTCPeerConnectionDelegate on its own threads, so a small
//  nonisolated observer forwards those events to the main queue.
//

import Foundation
import AVFoundation
@preconcurrency import WebRTC

@MainActor
protocol WebRTCClientDelegate: AnyObject {
    func webRTCClient(_ client: WebRTCClient, didGenerateLocalCandidate candidate: SignalingIceCandidate)
    func webRTCClient(_ client: WebRTCClient, didChangeIceConnectionState state: RTCIceConnectionState)
    func webRTCClient(_ client: WebRTCClient, didChangePeerConnectionState state: RTCPeerConnectionState)
}

enum WebRTCClientError: LocalizedError {
    case peerConnectionUnavailable
    case closed

    var errorDescription: String? {
        switch self {
        case .peerConnectionUnavailable: return "Could not create the peer connection"
        case .closed: return "The peer connection is closed"
        }
    }
}

@MainActor
final class WebRTCClient {

    // MARK: Process-wide setup

    /// Whether calls use `EngineAudioDevice` (the app owns the audio I/O and
    /// can tap the microphone for transcription) instead of WebRTC's built-in
    /// audio unit. Fixed at launch; `useBuiltInWebRTCAudio` is an escape hatch.
    static let usesEngineAudioDevice: Bool =
        !UserDefaults.standard.bool(forKey: Constants.UserDefaults.useBuiltInWebRTCAudio)

    /// Shared factory. Creating it initializes the WebRTC threads once.
    private static let factory: RTCPeerConnectionFactory = {
        RTCInitializeSSL()
        RTCSetMinDebugLogLevel(.warning)
        if usesEngineAudioDevice {
            print("🎧 [WebRTC] Using the AVAudioEngine audio device")
            return RTCPeerConnectionFactory(
                encoderFactory: RTCDefaultVideoEncoderFactory(),
                decoderFactory: RTCDefaultVideoDecoderFactory(),
                audioDevice: EngineAudioDevice.shared
            )
        }
        print("🎧 [WebRTC] Using WebRTC's built-in audio unit (transcription unavailable)")
        return RTCPeerConnectionFactory(
            encoderFactory: RTCDefaultVideoEncoderFactory(),
            decoderFactory: RTCDefaultVideoDecoderFactory()
        )
    }()

    /// Call once at app launch. Configures the audio session hand-off with CallKit.
    static func initialize() {
        _ = factory
        let session = RTCAudioSession.sharedInstance()
        #if targetEnvironment(simulator)
        // Starting the voice-processing audio unit in the simulator can
        // deadlock CoreAudio, which then aborts the process ("Initialize: RPC
        // timeout. Apparently deadlocked"). Audio capture/playout therefore
        // stays off in the simulator unless explicitly enabled with
        //   xcrun simctl spawn <udid> defaults write com.D3DigitalProductions.WebRTCDialer simulatorAudioEnabled -bool YES
        // ICE/DTLS still connect and signaling works; only RTP audio is absent.
        let audioEnabled = simulatorAudioEnabled
        session.useManualAudio = !audioEnabled
        session.isAudioEnabled = audioEnabled
        print("🎧 [WebRTC] Simulator audio unit \(audioEnabled ? "enabled" : "disabled (set simulatorAudioEnabled to enable)")")
        #else
        // On device CallKit owns the audio session: WebRTC must not start its
        // audio unit until provider(_:didActivate:) fires.
        session.useManualAudio = true
        session.isAudioEnabled = false
        #endif
    }

    // MARK: Instance state

    weak var delegate: WebRTCClientDelegate?

    let hasVideo: Bool

    private var peerConnection: RTCPeerConnection?
    private var observer: PeerConnectionObserver?
    private var audioTrack: RTCAudioTrack?
    private var remoteDescriptionSet = false
    private var pendingRemoteCandidates: [SignalingIceCandidate] = []
    private var statsTimer: Timer?

    private(set) var iceConnectionState: RTCIceConnectionState = .new
    private(set) var connectionState: RTCPeerConnectionState = .new

    private static let sdpConstraints = RTCMediaConstraints(
        mandatoryConstraints: ["OfferToReceiveAudio": "true", "OfferToReceiveVideo": "false"],
        optionalConstraints: nil
    )

    init(iceServers: [RTCIceServer]? = nil, hasVideo: Bool = false) throws {
        self.hasVideo = hasVideo
        let iceServers = iceServers ?? WebRTCClient.defaultIceServers()

        let config = RTCConfiguration()
        config.iceServers = iceServers
        config.sdpSemantics = .unifiedPlan
        config.continualGatheringPolicy = .gatherContinually
        config.bundlePolicy = .maxBundle
        config.rtcpMuxPolicy = .require

        let observer = PeerConnectionObserver()
        guard let pc = WebRTCClient.factory.peerConnection(
            with: config,
            constraints: RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil),
            delegate: observer
        ) else {
            throw WebRTCClientError.peerConnectionUnavailable
        }

        self.observer = observer
        self.peerConnection = pc
        observer.owner = self

        addLocalAudioTrack()
        log("Peer connection created (ice servers: \(iceServers.flatMap { $0.urlStrings }))")
    }

    /// Whether the simulator should start the real audio unit (see `initialize`).
    static var simulatorAudioEnabled: Bool {
        UserDefaults.standard.bool(forKey: Constants.UserDefaults.simulatorAudioEnabled)
    }

    /// STUN (and TURN when real credentials are configured) from Constants.
    static func defaultIceServers() -> [RTCIceServer] {
        var servers = [RTCIceServer(urlStrings: Constants.ICE.stunServers)]
        let turn = Constants.ICE.turnServer
        if !turn.isEmpty, !turn.contains("your-turn-server") {
            servers.append(RTCIceServer(
                urlStrings: [turn],
                username: Constants.ICE.turnUsername,
                credential: Constants.ICE.turnPassword
            ))
        }
        return servers
    }

    // MARK: Local media

    private func addLocalAudioTrack() {
        guard let pc = peerConnection else { return }
        let source = WebRTCClient.factory.audioSource(with: RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil))
        let track = WebRTCClient.factory.audioTrack(with: source, trackId: "audio0")
        pc.add(track, streamIds: ["stream0"])
        audioTrack = track
    }

    var isMuted: Bool {
        get { !(audioTrack?.isEnabled ?? true) }
        set { audioTrack?.isEnabled = !newValue; log("Microphone \(newValue ? "muted" : "unmuted")") }
    }

    // MARK: Offer / answer

    func createOffer() async throws -> String {
        guard let pc = peerConnection else { throw WebRTCClientError.closed }
        let sdp = try await pc.offer(for: WebRTCClient.sdpConstraints)
        try await pc.setLocalDescription(sdp)
        log("Local offer set")
        return sdp.sdp
    }

    func createAnswer() async throws -> String {
        guard let pc = peerConnection else { throw WebRTCClientError.closed }
        let sdp = try await pc.answer(for: WebRTCClient.sdpConstraints)
        try await pc.setLocalDescription(sdp)
        log("Local answer set")
        return sdp.sdp
    }

    func setRemoteOffer(_ sdp: String) async throws {
        try await setRemoteDescription(RTCSessionDescription(type: .offer, sdp: sdp))
    }

    func setRemoteAnswer(_ sdp: String) async throws {
        try await setRemoteDescription(RTCSessionDescription(type: .answer, sdp: sdp))
    }

    private func setRemoteDescription(_ description: RTCSessionDescription) async throws {
        guard let pc = peerConnection else { throw WebRTCClientError.closed }
        try await pc.setRemoteDescription(description)
        remoteDescriptionSet = true
        log("Remote \(RTCSessionDescription.string(for: description.type)) set")
        let queued = pendingRemoteCandidates
        pendingRemoteCandidates.removeAll()
        for candidate in queued {
            await addRemoteCandidateNow(candidate)
        }
        if !queued.isEmpty { log("Applied \(queued.count) queued remote candidate(s)") }
    }

    // MARK: ICE

    /// Remote candidates may arrive before the remote description (trickle ICE);
    /// they are queued until it is set.
    func addRemoteCandidate(_ candidate: SignalingIceCandidate) {
        guard peerConnection != nil else { return }
        if remoteDescriptionSet {
            Task { await addRemoteCandidateNow(candidate) }
        } else {
            pendingRemoteCandidates.append(candidate)
        }
    }

    private func addRemoteCandidateNow(_ candidate: SignalingIceCandidate) async {
        guard let pc = peerConnection else { return }
        let rtcCandidate = RTCIceCandidate(sdp: candidate.sdp, sdpMLineIndex: candidate.sdpMLineIndex, sdpMid: candidate.sdpMid)
        do {
            try await pc.add(rtcCandidate)
        } catch {
            log("Failed to add remote candidate: \(error.localizedDescription)")
        }
    }

    // MARK: Audio routing

    /// Apply the voice-chat audio session configuration. Call before the first
    /// offer/answer (and from the CallKit start/answer actions).
    static func configureAudioSession() {
        let session = RTCAudioSession.sharedInstance()
        session.lockForConfiguration()
        defer { session.unlockForConfiguration() }
        let configuration = RTCAudioSessionConfiguration.webRTC()
        configuration.category = AVAudioSession.Category.playAndRecord.rawValue
        configuration.mode = AVAudioSession.Mode.voiceChat.rawValue
        configuration.categoryOptions = [.allowBluetoothHFP, .allowBluetoothA2DP]
        do {
            try session.setConfiguration(configuration)
        } catch {
            print("🎧 [WebRTC] Audio session configuration failed: \(error.localizedDescription)")
        }
    }

    /// Activate the audio session ourselves. Only needed when CallKit is not
    /// driving the session (simulator, or a CallKit transaction that failed).
    static func activateAudioSession(_ active: Bool) {
        let session = RTCAudioSession.sharedInstance()
        session.lockForConfiguration()
        defer { session.unlockForConfiguration() }
        do {
            try session.setActive(active)
        } catch {
            print("🎧 [WebRTC] setActive(\(active)) failed: \(error.localizedDescription)")
        }
        if usesEngineAudioDevice { EngineAudioDevice.shared.setAudioSessionActive(active) }
    }

    /// Hand CallKit's audio session activation to WebRTC (device only).
    static func audioSessionDidActivate(_ avSession: AVAudioSession) {
        let session = RTCAudioSession.sharedInstance()
        session.audioSessionDidActivate(avSession)
        session.isAudioEnabled = true
        if usesEngineAudioDevice { EngineAudioDevice.shared.setAudioSessionActive(true) }
    }

    static func audioSessionDidDeactivate(_ avSession: AVAudioSession) {
        if usesEngineAudioDevice { EngineAudioDevice.shared.setAudioSessionActive(false) }
        let session = RTCAudioSession.sharedInstance()
        session.isAudioEnabled = false
        session.audioSessionDidDeactivate(avSession)
    }

    func setSpeakerEnabled(_ enabled: Bool) {
        let session = RTCAudioSession.sharedInstance()
        session.lockForConfiguration()
        defer { session.unlockForConfiguration() }
        do {
            try session.overrideOutputAudioPort(enabled ? .speaker : .none)
            log("Speaker \(enabled ? "on" : "off")")
        } catch {
            log("Speaker override failed: \(error.localizedDescription)")
        }
    }

    // MARK: DTMF

    @discardableResult
    func sendDTMF(_ tones: String) -> Bool {
        guard let pc = peerConnection,
              let sender = pc.senders.first(where: { $0.track?.kind == kRTCMediaStreamTrackKindAudio }),
              let dtmf = sender.dtmfSender, dtmf.canInsertDtmf else {
            log("DTMF unavailable (no audio sender or not connected)")
            return false
        }
        let ok = dtmf.insertDtmf(tones, duration: 0.1, interToneGap: 0.07)
        log("DTMF '\(tones)' \(ok ? "queued" : "rejected")")
        return ok
    }

    // MARK: Statistics

    struct AudioStats: CustomStringConvertible {
        var packetsSent: Int = 0
        var bytesSent: Int = 0
        var packetsReceived: Int = 0
        var bytesReceived: Int = 0
        var packetsLost: Int = 0
        var roundTripTimeMs: Double?
        /// Bytes over the selected ICE candidate pair (RTP + RTCP + DTLS).
        var transportBytesSent: Int = 0
        var transportBytesReceived: Int = 0

        var description: String {
            var parts = [
                "audio sent \(packetsSent) pkts/\(bytesSent) B",
                "audio received \(packetsReceived) pkts/\(bytesReceived) B",
                "lost \(packetsLost)",
                "transport \(transportBytesSent) B out/\(transportBytesReceived) B in"
            ]
            if let rtt = roundTripTimeMs { parts.append(String(format: "rtt %.0f ms", rtt)) }
            return parts.joined(separator: ", ")
        }
    }

    func audioStatistics() async -> AudioStats {
        guard let pc = peerConnection else { return AudioStats() }
        let report = await pc.statistics()
        var stats = AudioStats()
        for stat in report.statistics.values {
            let values = stat.values
            switch stat.type {
            case "outbound-rtp" where (values["kind"] as? String) == "audio":
                stats.packetsSent += (values["packetsSent"] as? NSNumber)?.intValue ?? 0
                stats.bytesSent += (values["bytesSent"] as? NSNumber)?.intValue ?? 0
            case "inbound-rtp" where (values["kind"] as? String) == "audio":
                stats.packetsReceived += (values["packetsReceived"] as? NSNumber)?.intValue ?? 0
                stats.bytesReceived += (values["bytesReceived"] as? NSNumber)?.intValue ?? 0
                stats.packetsLost += (values["packetsLost"] as? NSNumber)?.intValue ?? 0
            case "candidate-pair" where (values["state"] as? String) == "succeeded" && (values["nominated"] as? Bool ?? true):
                if let rtt = (values["currentRoundTripTime"] as? NSNumber)?.doubleValue {
                    stats.roundTripTimeMs = rtt * 1000
                }
                stats.transportBytesSent += (values["bytesSent"] as? NSNumber)?.intValue ?? 0
                stats.transportBytesReceived += (values["bytesReceived"] as? NSNumber)?.intValue ?? 0
            default:
                break
            }
        }
        return stats
    }

    /// Log audio packet counters periodically (useful on the simulator, which
    /// has no microphone: packets still flow because WebRTC sends silence/CN).
    func startStatsLogging(every interval: TimeInterval = 5) {
        stopStatsLogging()
        statsTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.peerConnection != nil else { return }
                let stats = await self.audioStatistics()
                self.log("Stats: \(stats) | ice=\(self.iceConnectionState.name) pc=\(self.connectionState.name)")
            }
        }
    }

    func stopStatsLogging() {
        statsTimer?.invalidate()
        statsTimer = nil
    }

    // MARK: Teardown

    func close() {
        stopStatsLogging()
        guard let pc = peerConnection else { return }
        log("Closing peer connection")
        observer?.owner = nil
        pc.close()
        peerConnection = nil
        audioTrack = nil
        observer = nil
        pendingRemoteCandidates.removeAll()
        remoteDescriptionSet = false
    }

    // MARK: Events from the observer (main actor)

    fileprivate func handleLocalCandidate(_ candidate: RTCIceCandidate) {
        let wire = SignalingIceCandidate(sdp: candidate.sdp, sdpMid: candidate.sdpMid, sdpMLineIndex: candidate.sdpMLineIndex)
        delegate?.webRTCClient(self, didGenerateLocalCandidate: wire)
    }

    fileprivate func handleIceConnectionState(_ state: RTCIceConnectionState) {
        iceConnectionState = state
        log("ICE connection state → \(state.name)")
        delegate?.webRTCClient(self, didChangeIceConnectionState: state)
    }

    fileprivate func handlePeerConnectionState(_ state: RTCPeerConnectionState) {
        connectionState = state
        log("Peer connection state → \(state.name)")
        delegate?.webRTCClient(self, didChangePeerConnectionState: state)
    }

    private func log(_ message: String) {
        print("🎧 [WebRTC] \(message)")
    }
}

// MARK: - RTCPeerConnectionDelegate bridge

/// Receives libwebrtc callbacks on WebRTC's threads and forwards them to the
/// owning client on the main queue, preserving order.
private final class PeerConnectionObserver: NSObject, RTCPeerConnectionDelegate, @unchecked Sendable {

    /// Accessed on the main thread only.
    nonisolated(unsafe) weak var owner: WebRTCClient?

    nonisolated private func onMain(_ work: @escaping @MainActor (WebRTCClient) -> Void) {
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                guard let owner = self.owner else { return }
                work(owner)
            }
        }
    }

    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {
        print("🎧 [WebRTC] Signaling state → \(stateChanged.rawValue)")
    }

    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {
        print("🎧 [WebRTC] Remote stream added: \(stream.audioTracks.count) audio, \(stream.videoTracks.count) video")
    }

    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {
        print("🎧 [WebRTC] Remote stream removed")
    }

    nonisolated func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {
        // Negotiation is driven explicitly by CallManager.
    }

    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
        onMain { $0.handleIceConnectionState(newState) }
    }

    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {
        print("🎧 [WebRTC] ICE gathering state → \(newState.rawValue)")
    }

    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        onMain { $0.handleLocalCandidate(candidate) }
    }

    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {
        // Not forwarded: the backend has no candidate-removal event.
    }

    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {
        // Data channels are not used.
    }

    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCPeerConnectionState) {
        onMain { $0.handlePeerConnectionState(newState) }
    }
}

// MARK: - Readable state names

extension RTCIceConnectionState {
    var name: String {
        switch self {
        case .new: return "new"
        case .checking: return "checking"
        case .connected: return "connected"
        case .completed: return "completed"
        case .failed: return "failed"
        case .disconnected: return "disconnected"
        case .closed: return "closed"
        case .count: return "count"
        @unknown default: return "unknown(\(rawValue))"
        }
    }
}

extension RTCPeerConnectionState {
    var name: String {
        switch self {
        case .new: return "new"
        case .connecting: return "connecting"
        case .connected: return "connected"
        case .disconnected: return "disconnected"
        case .failed: return "failed"
        case .closed: return "closed"
        @unknown default: return "unknown(\(rawValue))"
        }
    }
}

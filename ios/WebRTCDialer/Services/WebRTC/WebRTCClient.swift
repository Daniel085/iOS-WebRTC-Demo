//
//  WebRTCClient.swift
//  WebRTCDialer
//
//  One RTCPeerConnection per call. Audio always; video is added behind
//  `hasVideo` (at call start) or mid-call through `setVideoEnabled`, which
//  renegotiates with a fresh offer that CallManager relays over signaling.
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
    /// A local media change (video on/off) produced a new offer that must be
    /// sent to the other party. The remote answer comes back via `setRemoteAnswer`.
    func webRTCClient(_ client: WebRTCClient, didCreateRenegotiationOffer sdp: String)
    /// The local camera track to preview (nil when video is off).
    func webRTCClient(_ client: WebRTCClient, didChangeLocalVideoTrack track: RTCVideoTrack?)
    /// The remote video track, non-nil only while the other party is sending video.
    func webRTCClient(_ client: WebRTCClient, didChangeRemoteVideoTrack track: RTCVideoTrack?)
}

enum WebRTCClientError: LocalizedError {
    case peerConnectionUnavailable
    case closed
    case noCamera
    case transceiverUnavailable

    var errorDescription: String? {
        switch self {
        case .peerConnectionUnavailable: return "Could not create the peer connection"
        case .closed: return "The peer connection is closed"
        case .noCamera: return "No camera is available"
        case .transceiverUnavailable: return "Could not add the video transceiver"
        }
    }
}

@MainActor
final class WebRTCClient {

    // MARK: Process-wide setup

    /// Shared factory. Creating it initializes the WebRTC threads once.
    private static let factory: RTCPeerConnectionFactory = {
        RTCInitializeSSL()
        RTCSetMinDebugLogLevel(.warning)
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

    weak var delegate: WebRTCClientDelegate? {
        didSet {
            // A video call creates its local track in init, before the
            // delegate exists; hand it over as soon as one is attached.
            if let track = localVideoTrack, isVideoEnabled {
                delegate?.webRTCClient(self, didChangeLocalVideoTrack: track)
            }
        }
    }

    /// Whether the call was set up as a video call (local video added before
    /// the first offer/answer). Video can still be turned on later.
    let hasVideo: Bool

    /// Perfect-negotiation role. The polite peer (the callee) rolls back its
    /// own pending offer when the other side's offer collides with it; the
    /// impolite peer ignores the colliding offer.
    let isPolite: Bool

    private var peerConnection: RTCPeerConnection?
    private var observer: PeerConnectionObserver?
    private var audioTrack: RTCAudioTrack?
    private var remoteDescriptionSet = false
    private var pendingRemoteCandidates: [SignalingIceCandidate] = []
    private var statsTimer: Timer?

    private(set) var iceConnectionState: RTCIceConnectionState = .new
    private(set) var connectionState: RTCPeerConnectionState = .new

    // Video
    private(set) var isVideoEnabled = false
    private(set) var localVideoTrack: RTCVideoTrack?
    private(set) var remoteVideoTrack: RTCVideoTrack?
    private(set) var cameraPosition: AVCaptureDevice.Position = .front
    private var videoSource: RTCVideoSource?
    private var videoTransceiver: RTCRtpTransceiver?
    private var cameraCapturer: RTCCameraVideoCapturer?
    private var syntheticCapturer: SyntheticVideoCapturer?
    /// A local change happened while an offer/answer exchange was in flight;
    /// a new offer is created as soon as signaling is back to `stable`.
    private var renegotiationPending = false

    /// Target camera format; the closest supported one is used.
    static let preferredVideoWidth: Int32 = 640
    static let preferredVideoHeight: Int32 = 480
    static let preferredVideoFps = 30

    init(iceServers: [RTCIceServer]? = nil, hasVideo: Bool = false, isPolite: Bool = false) throws {
        self.hasVideo = hasVideo
        self.isPolite = isPolite
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

        if hasVideo {
            // The transceiver must exist before the first offer/answer; the
            // capturer starts asynchronously and feeds frames once it is up.
            do {
                try attachLocalVideo()
                Task { [weak self] in await self?.startVideoCapture() }
            } catch {
                log("Could not add video: \(error.localizedDescription)")
            }
        }
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

    // MARK: Local audio

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

    // MARK: Local video

    /// Turn the camera on or off. Turning it on adds (or re-activates) the
    /// video transceiver and starts capture; turning it off stops capture and
    /// makes the transceiver receive-only. Both renegotiate: the new offer is
    /// handed to the delegate (or deferred until the current exchange ends).
    func setVideoEnabled(_ enabled: Bool) async throws {
        guard peerConnection != nil else { throw WebRTCClientError.closed }
        guard enabled != isVideoEnabled else { return }
        if enabled {
            try attachLocalVideo()
            await startVideoCapture()
        } else {
            await stopVideoCapture()
            localVideoTrack?.isEnabled = false
            if let transceiver = videoTransceiver {
                try WebRTCClient.setDirection(.recvOnly, on: transceiver)
            }
            isVideoEnabled = false
            log("Local video disabled")
            delegate?.webRTCClient(self, didChangeLocalVideoTrack: nil)
        }
        await renegotiate()
    }

    /// Switch between the front and back camera (on the simulator, between
    /// the two synthetic test patterns).
    func switchCamera() {
        cameraPosition = (cameraPosition == .front) ? .back : .front
        log("Camera position → \(cameraPosition == .front ? "front" : "back")")
        guard isVideoEnabled else { return }
        if let synthetic = syntheticCapturer {
            synthetic.pattern = (cameraPosition == .front) ? .front : .back
            return
        }
        Task { [weak self] in
            guard let self else { return }
            await self.stopVideoCapture()
            await self.startVideoCapture()
        }
    }

    /// `setDirection:error:` is not imported as `throws` (its name clashes with
    /// the `direction` setter), so bridge the NSError by hand.
    private static func setDirection(_ direction: RTCRtpTransceiverDirection, on transceiver: RTCRtpTransceiver) throws {
        var error: NSError?
        transceiver.setDirection(direction, error: &error)
        if let error { throw error }
    }

    /// Create the local video track/transceiver (idempotent) and mark it as sending.
    private func attachLocalVideo() throws {
        guard let pc = peerConnection else { throw WebRTCClientError.closed }
        let track: RTCVideoTrack
        if let existing = localVideoTrack {
            track = existing
        } else {
            let source = WebRTCClient.factory.videoSource()
            track = WebRTCClient.factory.videoTrack(with: source, trackId: "video0")
            videoSource = source
            localVideoTrack = track
        }
        track.isEnabled = true

        if let transceiver = videoTransceiver
            ?? pc.transceivers.first(where: { $0.mediaType == .video && !$0.isStopped }) {
            // Either our own (video was turned off earlier) or one the remote
            // offer created for its video: reuse it and send on it too.
            transceiver.sender.track = track
            transceiver.sender.streamIds = ["stream0"]
            try WebRTCClient.setDirection(.sendRecv, on: transceiver)
            videoTransceiver = transceiver
            log("Video transceiver reused (mid \(transceiver.mid)) → sendrecv")
        } else {
            // addTrack, not addTransceiver: only transceivers created by
            // addTrack may be associated with a video m-line in a remote offer
            // (JSEP 5.10), which is what lets the callee answer sendrecv.
            guard let sender = pc.add(track, streamIds: ["stream0"]),
                  let transceiver = pc.transceivers.first(where: { $0.sender == sender }) else {
                throw WebRTCClientError.transceiverUnavailable
            }
            videoTransceiver = transceiver
            log("Video transceiver added (sendrecv, \(WebRTCClient.preferredVideoWidth)x\(WebRTCClient.preferredVideoHeight)@\(WebRTCClient.preferredVideoFps))")
        }
        isVideoEnabled = true
        delegate?.webRTCClient(self, didChangeLocalVideoTrack: track)
    }

    private func startVideoCapture() async {
        guard let source = videoSource, isVideoEnabled else { return }
        if cameraCapturer != nil || syntheticCapturer != nil { return }

        let devices = RTCCameraVideoCapturer.captureDevices()
        guard let device = devices.first(where: { $0.position == cameraPosition }) ?? devices.first else {
            // The iOS simulator has no camera: feed a generated test pattern so
            // the video track still negotiates and carries frames.
            let synthetic = SyntheticVideoCapturer(delegate: source)
            synthetic.pattern = (cameraPosition == .front) ? .front : .back
            synthetic.start()
            syntheticCapturer = synthetic
            log("No camera available (simulator?); using a synthetic video source")
            return
        }

        guard let format = WebRTCClient.bestFormat(for: device) else {
            log("Camera \(device.localizedName) has no usable formats")
            return
        }
        let fps = WebRTCClient.bestFrameRate(for: format)
        let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
        let capturer = RTCCameraVideoCapturer(delegate: source)
        cameraCapturer = capturer
        let error: Error? = await withCheckedContinuation { continuation in
            capturer.startCapture(with: device, format: format, fps: fps) { error in
                continuation.resume(returning: error)
            }
        }
        if let error {
            log("Camera start failed: \(error.localizedDescription)")
            cameraCapturer = nil
        } else {
            log("Camera started: \(device.localizedName) \(dimensions.width)x\(dimensions.height)@\(fps)")
        }
    }

    private func stopVideoCapture() async {
        if let synthetic = syntheticCapturer {
            synthetic.stop()
            syntheticCapturer = nil
        }
        if let capturer = cameraCapturer {
            cameraCapturer = nil
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                capturer.stopCapture { continuation.resume() }
            }
            log("Camera stopped")
        }
    }

    /// The supported format closest to 640x480 whose pixel format WebRTC
    /// can consume directly.
    static func bestFormat(for device: AVCaptureDevice) -> AVCaptureDevice.Format? {
        let formats = RTCCameraVideoCapturer.supportedFormats(for: device)
        let supportedPixelFormats = RTCCVPixelBuffer.supportedPixelFormats()
        let targetArea = Int(preferredVideoWidth) * Int(preferredVideoHeight)
        func score(_ format: AVCaptureDevice.Format) -> Int {
            let dims = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            let areaDelta = abs(Int(dims.width) * Int(dims.height) - targetArea)
            let pixelFormat = CMFormatDescriptionGetMediaSubType(format.formatDescription)
            let penalty = supportedPixelFormats.contains(NSNumber(value: pixelFormat)) ? 0 : 10_000_000
            return areaDelta + penalty
        }
        return formats.min { score($0) < score($1) }
    }

    static func bestFrameRate(for format: AVCaptureDevice.Format) -> Int {
        let maxSupported = format.videoSupportedFrameRateRanges.map(\.maxFrameRate).max() ?? Double(preferredVideoFps)
        return min(preferredVideoFps, Int(maxSupported))
    }

    // MARK: Offer / answer

    /// `OfferToReceiveVideo` stays false until a video transceiver exists, so
    /// an audio-only call produces exactly the SDP it always did.
    private func sdpConstraints() -> RTCMediaConstraints {
        let wantsVideo = peerConnection?.transceivers.contains { $0.mediaType == .video && !$0.isStopped } ?? false
        return RTCMediaConstraints(
            mandatoryConstraints: ["OfferToReceiveAudio": "true", "OfferToReceiveVideo": wantsVideo ? "true" : "false"],
            optionalConstraints: nil
        )
    }

    func createOffer() async throws -> String {
        guard let pc = peerConnection else { throw WebRTCClientError.closed }
        let sdp = try await pc.offer(for: sdpConstraints())
        try await pc.setLocalDescription(sdp)
        log("Local offer set")
        logTransceivers()
        return sdp.sdp
    }

    func createAnswer() async throws -> String {
        guard let pc = peerConnection else { throw WebRTCClientError.closed }
        let sdp = try await pc.answer(for: sdpConstraints())
        try await pc.setLocalDescription(sdp)
        log("Local answer set")
        logTransceivers()
        refreshRemoteVideo()
        if pc.signalingState == .stable { await resumePendingRenegotiation() }
        return sdp.sdp
    }

    func setRemoteOffer(_ sdp: String) async throws {
        try await setRemoteDescription(RTCSessionDescription(type: .offer, sdp: sdp))
    }

    /// Apply a remote offer (initial or renegotiation) and produce the answer.
    /// Returns nil when the offer collided with our own pending offer and this
    /// is the impolite peer: the other side rolls back and re-offers.
    func handleRemoteOffer(_ sdp: String) async throws -> String? {
        guard let pc = peerConnection else { throw WebRTCClientError.closed }
        if pc.signalingState != .stable {
            guard isPolite else {
                log("Ignoring remote offer while our own offer is pending (glare, impolite peer)")
                return nil
            }
            log("Rolling back our pending offer to take the remote one (glare, polite peer)")
            try await pc.setLocalDescription(RTCSessionDescription(type: .rollback, sdp: ""))
            renegotiationPending = true
        }
        try await setRemoteOffer(sdp)
        return try await createAnswer()
    }

    func setRemoteAnswer(_ sdp: String) async throws {
        guard let pc = peerConnection else { throw WebRTCClientError.closed }
        guard pc.signalingState == .haveLocalOffer else {
            log("Ignoring remote answer in signaling state \(pc.signalingState.rawValue) (stale after rollback?)")
            return
        }
        try await setRemoteDescription(RTCSessionDescription(type: .answer, sdp: sdp))
        await resumePendingRenegotiation()
    }

    private func setRemoteDescription(_ description: RTCSessionDescription) async throws {
        guard let pc = peerConnection else { throw WebRTCClientError.closed }
        try await pc.setRemoteDescription(description)
        remoteDescriptionSet = true
        log("Remote \(RTCSessionDescription.string(for: description.type)) set")
        logTransceivers()
        refreshRemoteVideo()
        let queued = pendingRemoteCandidates
        pendingRemoteCandidates.removeAll()
        for candidate in queued {
            await addRemoteCandidateNow(candidate)
        }
        if !queued.isEmpty { log("Applied \(queued.count) queued remote candidate(s)") }
    }

    // MARK: Renegotiation

    /// Create a new offer for a local media change and hand it to the delegate.
    /// Deferred while an offer/answer exchange is in flight.
    private func renegotiate() async {
        guard let pc = peerConnection else { return }
        guard pc.signalingState == .stable else {
            renegotiationPending = true
            log("Renegotiation deferred (signaling state \(pc.signalingState.rawValue))")
            return
        }
        renegotiationPending = false
        do {
            let sdp = try await createOffer()
            log("Renegotiation offer created")
            delegate?.webRTCClient(self, didCreateRenegotiationOffer: sdp)
        } catch {
            log("Renegotiation offer failed: \(error.localizedDescription)")
        }
    }

    private func resumePendingRenegotiation() async {
        guard renegotiationPending, peerConnection?.signalingState == .stable else { return }
        log("Resuming deferred renegotiation")
        await renegotiate()
    }

    // MARK: Remote video

    /// Publish the remote video track only while the negotiated direction says
    /// the other party is sending video; a muted/receive-only transceiver
    /// means its camera is off.
    fileprivate func refreshRemoteVideo() {
        guard let pc = peerConnection else { return }
        var active: RTCVideoTrack?
        for transceiver in pc.transceivers where transceiver.mediaType == .video && !transceiver.isStopped {
            var direction = RTCRtpTransceiverDirection.inactive
            guard transceiver.currentDirection(&direction) else { continue }
            if direction == .sendRecv || direction == .recvOnly,
               let track = transceiver.receiver.track as? RTCVideoTrack {
                active = track
                break
            }
        }
        // `receiver.track` returns a fresh wrapper object each time, so compare ids.
        guard active?.trackId != remoteVideoTrack?.trackId else { return }
        remoteVideoTrack = active
        log("Remote video \(active == nil ? "stopped" : "active")")
        delegate?.webRTCClient(self, didChangeRemoteVideoTrack: active)
    }

    private func logTransceivers() {
        guard let pc = peerConnection else { return }
        let parts = pc.transceivers.map { transceiver -> String in
            let kind = transceiver.mediaType == .video ? "video" : "audio"
            var current = RTCRtpTransceiverDirection.inactive
            let negotiated = transceiver.currentDirection(&current) ? current.name : "-"
            return "\(kind)[mid \(transceiver.mid)] \(transceiver.direction.name)/\(negotiated)"
        }
        log("Transceivers (preferred/negotiated): \(parts.joined(separator: ", "))")
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
    }

    /// Hand CallKit's audio session activation to WebRTC (device only).
    static func audioSessionDidActivate(_ avSession: AVAudioSession) {
        let session = RTCAudioSession.sharedInstance()
        session.audioSessionDidActivate(avSession)
        session.isAudioEnabled = true
    }

    static func audioSessionDidDeactivate(_ avSession: AVAudioSession) {
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
        /// Video counters; all zero (and omitted from `description`) on audio-only calls.
        var videoPacketsSent: Int = 0
        var videoFramesEncoded: Int = 0
        var videoPacketsReceived: Int = 0
        var videoFramesDecoded: Int = 0

        var hasVideoActivity: Bool {
            videoPacketsSent + videoFramesEncoded + videoPacketsReceived + videoFramesDecoded > 0
        }

        var description: String {
            var parts = [
                "audio sent \(packetsSent) pkts/\(bytesSent) B",
                "audio received \(packetsReceived) pkts/\(bytesReceived) B",
                "lost \(packetsLost)",
                "transport \(transportBytesSent) B out/\(transportBytesReceived) B in"
            ]
            if hasVideoActivity {
                parts.append("video sent \(videoPacketsSent) pkts/\(videoFramesEncoded) frames")
                parts.append("video received \(videoPacketsReceived) pkts/\(videoFramesDecoded) frames")
            }
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
            let kind = values["kind"] as? String
            switch stat.type {
            case "outbound-rtp" where kind == "audio":
                stats.packetsSent += (values["packetsSent"] as? NSNumber)?.intValue ?? 0
                stats.bytesSent += (values["bytesSent"] as? NSNumber)?.intValue ?? 0
            case "inbound-rtp" where kind == "audio":
                stats.packetsReceived += (values["packetsReceived"] as? NSNumber)?.intValue ?? 0
                stats.bytesReceived += (values["bytesReceived"] as? NSNumber)?.intValue ?? 0
                stats.packetsLost += (values["packetsLost"] as? NSNumber)?.intValue ?? 0
            case "outbound-rtp" where kind == "video":
                stats.videoPacketsSent += (values["packetsSent"] as? NSNumber)?.intValue ?? 0
                stats.videoFramesEncoded += (values["framesEncoded"] as? NSNumber)?.intValue ?? 0
            case "inbound-rtp" where kind == "video":
                stats.videoPacketsReceived += (values["packetsReceived"] as? NSNumber)?.intValue ?? 0
                stats.videoFramesDecoded += (values["framesDecoded"] as? NSNumber)?.intValue ?? 0
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
        syntheticCapturer?.stop()
        syntheticCapturer = nil
        if let capturer = cameraCapturer {
            cameraCapturer = nil
            capturer.stopCapture()
        }
        pc.close()
        peerConnection = nil
        audioTrack = nil
        localVideoTrack = nil
        remoteVideoTrack = nil
        videoSource = nil
        videoTransceiver = nil
        isVideoEnabled = false
        observer = nil
        pendingRemoteCandidates.removeAll()
        remoteDescriptionSet = false
        renegotiationPending = false
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

    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didAdd rtpReceiver: RTCRtpReceiver, streams mediaStreams: [RTCMediaStream]) {
        let kind = rtpReceiver.track?.kind ?? "unknown"
        print("🎧 [WebRTC] Remote \(kind) receiver added (\(mediaStreams.count) stream(s))")
        if kind == kRTCMediaStreamTrackKindVideo { onMain { $0.refreshRemoteVideo() } }
    }

    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didRemove rtpReceiver: RTCRtpReceiver) {
        print("🎧 [WebRTC] Remote \(rtpReceiver.track?.kind ?? "unknown") receiver removed")
        onMain { $0.refreshRemoteVideo() }
    }

    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didStartReceivingOn transceiver: RTCRtpTransceiver) {
        print("🎧 [WebRTC] Started receiving on \(transceiver.mediaType == .video ? "video" : "audio") transceiver (mid \(transceiver.mid))")
        onMain { $0.refreshRemoteVideo() }
    }

    nonisolated func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {
        // Negotiation is driven explicitly: CallManager for the first exchange,
        // WebRTCClient.renegotiate() for video changes.
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

extension RTCRtpTransceiverDirection {
    var name: String {
        switch self {
        case .sendRecv: return "sendrecv"
        case .sendOnly: return "sendonly"
        case .recvOnly: return "recvonly"
        case .inactive: return "inactive"
        case .stopped: return "stopped"
        @unknown default: return "unknown(\(rawValue))"
        }
    }
}

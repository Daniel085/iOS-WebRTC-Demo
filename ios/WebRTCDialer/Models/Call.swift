//
//  Call.swift
//  WebRTCDialer
//
//  Call model plus CallManager, the single orchestrator for a call:
//  CallKit (system UI/audio session) ↔ SignalingClient (Socket.IO) ↔ WebRTCClient.
//
//  A future SIP gateway replaces the far end but not this flow: it would still
//  go through SignalingClient (or a sibling) and WebRTCClient.
//

import Foundation
import SwiftUI
import Combine
import CallKit
import AVFoundation
import WebRTC

/// Represents a call session
class Call: Identifiable, ObservableObject {
    let id: UUID

    /// Identifier used on the signaling channel. Equal to `id.uuidString` for
    /// outgoing calls; for incoming calls it is whatever the caller sent.
    let signalingCallId: String

    let phoneNumber: String

    /// Whether this is a video call
    var hasVideo: Bool

    /// Compatibility alias used by some views
    var isVideo: Bool { hasVideo }

    /// Whether this is an incoming call (vs outgoing)
    let isIncoming: Bool

    /// Convenience computed property
    var isOutgoing: Bool { !isIncoming }

    /// Current call state
    @Published var state: CallState = .idle

    /// Extra detail shown next to the state (e.g. "User not found")
    @Published var statusDetail: String?

    /// Whether audio is muted
    @Published var isMuted: Bool = false

    /// Whether speaker is enabled
    @Published var isSpeakerOn: Bool = false

    /// Whether call is on hold
    @Published var isOnHold: Bool = false

    /// Whether the local camera is on (sending video)
    @Published var isVideoEnabled: Bool

    /// Local camera track for the self-view; nil while the camera is off.
    @Published var localVideoTrack: RTCVideoTrack?

    /// Remote video track; nil while the other party is not sending video.
    @Published var remoteVideoTrack: RTCVideoTrack?

    /// Which camera the self-view shows (front is mirrored).
    @Published var isFrontCamera: Bool = true

    /// Whether the in-call UI should use the video layout.
    var showsVideo: Bool { isVideoEnabled || remoteVideoTrack != nil }

    /// When the call connected
    var connectedAt: Date?

    /// When the call ended
    var endedAt: Date?

    /// Call duration
    var duration: TimeInterval {
        guard let connectedAt = connectedAt else { return 0 }
        let endTime = endedAt ?? Date()
        return endTime.timeIntervalSince(connectedAt)
    }

    init(
        id: UUID = UUID(),
        signalingCallId: String? = nil,
        phoneNumber: String,
        isIncoming: Bool = false,
        hasVideo: Bool = false,
        state: CallState = .idle
    ) {
        self.id = id
        self.signalingCallId = signalingCallId ?? id.uuidString
        self.phoneNumber = phoneNumber
        self.isIncoming = isIncoming
        self.hasVideo = hasVideo
        self.isVideoEnabled = hasVideo
        self.state = state
    }

    /// Convenience initializer for backward compatibility
    convenience init(id: UUID = UUID(), phoneNumber: String, isVideo: Bool, isOutgoing: Bool = true) {
        self.init(id: id, phoneNumber: phoneNumber, isIncoming: !isOutgoing, hasVideo: isVideo)
    }

    /// Start the call
    func start() {
        state = isOutgoing ? .connecting : .ringing
    }

    /// Connect the call
    func connect() {
        guard state != .connected else { return }
        state = .connected
        connectedAt = Date()
    }

    /// End the call
    func end() {
        state = .ended
        endedAt = Date()
    }

    /// Mark the call as failed
    func fail() {
        state = .failed
        endedAt = Date()
    }

    var isFinished: Bool { state == .ended || state == .failed }
}

/// Call state enumeration
enum CallState {
    case idle
    case connecting
    case ringing
    case connected
    case ended
    case failed

    var description: String {
        switch self {
        case .idle: return "Idle"
        case .connecting: return "Connecting..."
        case .ringing: return "Ringing..."
        case .connected: return "Connected"
        case .ended: return "Call Ended"
        case .failed: return "Call Failed"
        }
    }
}

// MARK: - CallManager

/// Call manager to handle active calls
@MainActor
final class CallManager: ObservableObject {
    static let shared = CallManager()

    /// Call shown full screen (accepted/outgoing). Driven by the manager; the
    /// views never set these directly.
    @Published var activeCall: Call?
    /// Call ringing in (not yet accepted).
    @Published var incomingCall: Call?

    /// Every live call by UUID. Lookups use this, not the published
    /// properties, so an asynchronous CallKit callback or permission prompt
    /// still finds the call after the UI has moved on.
    private var calls: [UUID: Call] = [:]

    /// The call the full-screen call UI should show, if any.
    var presentedCall: Call? { activeCall ?? incomingCall }

    /// Outgoing/incoming calls whose start/answer action has been performed.
    private var answeredCalls: Set<UUID> = []

    /// Mirrors `SignalingClient.state` for the UI.
    @Published private(set) var signalingState: SignalingClient.ConnectionState = .disconnected

    let signaling = SignalingClient()

    private let callKit = CallKitManager.shared
    private let push = VoIPPushService.shared

    private var webRTC: WebRTCClient?

    /// Remote offers/candidates that arrived before the call was answered or
    /// before the peer connection existed.
    private var pendingOffers: [String: String] = [:]
    private var pendingCandidates: [String: [SignalingIceCandidate]] = [:]

    /// Outgoing calls whose CXStartCallAction has already been performed.
    private var startedCalls: Set<UUID> = []

    private var ringTimeoutTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    /// How long an outgoing call rings before giving up.
    private let ringTimeout: TimeInterval = 60

    /// CallKit drives call actions on a device. The simulator's CallKit ends
    /// outgoing calls immediately after they start, so there the manager
    /// performs the actions directly and the in-app call UI is used instead.
    #if targetEnvironment(simulator)
    let useCallKit = false
    #else
    let useCallKit = true
    #endif

    private init() {
        signaling.delegate = self
        callKit.delegate = self
        signaling.$state
            .sink { [weak self] state in self?.signalingState = state }
            .store(in: &cancellables)
    }

    // MARK: Lifecycle

    /// Call once at launch.
    func bootstrap() {
        WebRTCClient.initialize()
        push.register()
    }

    /// Connect signaling for the authenticated user.
    func connectSignaling() {
        signaling.connect()
        push.uploadTokenIfNeeded()
    }

    /// Tear everything down (logout).
    func disconnectSignaling() {
        if let call = activeCall ?? incomingCall {
            signaling.endCall(callId: call.signalingCallId)
            finish(call, state: .ended, detail: "Signed out", callKitReason: .failed, clearImmediately: true)
        }
        signaling.disconnect()
    }

    // MARK: Outgoing calls

    /// Initiate an outgoing call (KeypadView / contacts).
    func startCall(to phoneNumber: String, hasVideo: Bool = false) {
        guard activeCall == nil, incomingCall == nil else {
            log("Ignoring startCall: a call is already in progress")
            return
        }

        let number = normalizeDialedNumber(phoneNumber)
        let call = Call(phoneNumber: number, isIncoming: false, hasVideo: hasVideo, state: .connecting)
        calls[call.id] = call
        activeCall = call
        log("Starting call \(call.signalingCallId) to \(number)")

        guard signaling.isConnected else {
            finish(call, state: .failed, detail: "Not connected to server", callKitReason: nil)
            return
        }

        Task { [weak self] in
            let granted = await AVAudioApplication.requestRecordPermission()
            if !granted { self?.log("Microphone permission denied; the call will carry silence") }
            if hasVideo { await CallManager.requestCameraPermission() }
            guard let self, self.activeCall?.id == call.id else { return }
            guard self.useCallKit else {
                _ = self.performStartCall(uuid: call.id)
                return
            }
            self.callKit.requestStartCall(uuid: call.id, handle: number, hasVideo: hasVideo) { [weak self] error in
                guard let self, error != nil, self.activeCall?.id == call.id else { return }
                // CallKit refused (e.g. restricted); still place the call.
                self.log("Starting call without CallKit")
                _ = self.performStartCall(uuid: call.id)
            }
        }
    }

    /// Backward-compatible alias.
    func startCall(to phoneNumber: String, isVideo: Bool) {
        startCall(to: phoneNumber, hasVideo: isVideo)
    }

    private func performStartCall(uuid: UUID) -> Bool {
        guard let call = findCall(uuid: uuid), call.isOutgoing, !call.isFinished else { return false }
        if startedCalls.contains(uuid) { return true }
        startedCalls.insert(uuid)

        prepareAudioSession()
        guard let client = makeWebRTCClient(hasVideo: call.hasVideo, isPolite: false) else {
            finish(call, state: .failed, detail: "WebRTC unavailable", callKitReason: nil)
            return false
        }

        // `call-initiate` must reach the server before the offer.
        signaling.initiateCall(to: call.phoneNumber, callId: call.signalingCallId, hasVideo: call.hasVideo)
        if useCallKit { callKit.reportOutgoingCallStartedConnecting(uuid: call.id) }
        call.state = .ringing
        startRingTimeout(for: call)

        Task { [weak self] in
            do {
                let sdp = try await client.createOffer()
                guard let self, self.activeCall?.id == call.id else { return }
                self.signaling.sendOffer(callId: call.signalingCallId, sdp: sdp)
            } catch {
                self?.finish(call, state: .failed, detail: "Offer failed: \(error.localizedDescription)", callKitReason: .failed)
            }
        }
        return true
    }

    private func startRingTimeout(for call: Call) {
        ringTimeoutTask?.cancel()
        ringTimeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(self?.ringTimeout ?? 60))
            guard !Task.isCancelled, let self, self.activeCall?.id == call.id, call.state == .ringing else { return }
            self.log("No answer after \(Int(self.ringTimeout)) s")
            self.signaling.endCall(callId: call.signalingCallId)
            self.finish(call, state: .ended, detail: "No answer", callKitReason: .unanswered)
        }
    }

    // MARK: Incoming calls

    /// Receive an incoming call (kept for previews/tests; the real path is the
    /// signaling delegate below).
    func receiveCall(from phoneNumber: String, isVideo: Bool) {
        let call = Call(phoneNumber: phoneNumber, isIncoming: true, hasVideo: isVideo, state: .ringing)
        calls[call.id] = call
        incomingCall = call
    }

    private func presentIncomingCall(callId: String, from: String, hasVideo: Bool, completion: (@MainActor () -> Void)? = nil) {
        let call = Call(
            id: UUID(uuidString: callId) ?? UUID(),
            signalingCallId: callId,
            phoneNumber: from,
            isIncoming: true,
            hasVideo: hasVideo,
            state: .ringing
        )
        calls[call.id] = call
        incomingCall = call
        log("Incoming call \(callId) from \(from)")

        guard useCallKit else {
            completion?()
            return
        }
        callKit.reportIncomingCall(uuid: call.id, handle: from, hasVideo: hasVideo) { [weak self] error in
            if let error {
                self?.log("CallKit did not accept the incoming call (\(error.localizedDescription)); using in-app UI only")
            }
            completion?()
        }
    }

    /// Answer the current incoming call (IncomingCallView).
    func answerCall() {
        guard let call = incomingCall, !call.isFinished else { return }
        // Move to the active screen right away; the media setup follows.
        incomingCall = nil
        activeCall = call
        call.state = .connecting
        Task { [weak self] in
            _ = await AVAudioApplication.requestRecordPermission()
            if call.hasVideo { await CallManager.requestCameraPermission() }
            guard let self, !call.isFinished else { return }
            guard self.useCallKit else {
                _ = self.performAnswerCall(uuid: call.id)
                return
            }
            self.callKit.requestAnswerCall(uuid: call.id) { [weak self] error in
                guard let self, error != nil else { return }
                self.log("Answering without CallKit")
                _ = self.performAnswerCall(uuid: call.id)
            }
        }
    }

    /// Alias used by IncomingCallView.
    func acceptCall() { answerCall() }

    private func performAnswerCall(uuid: UUID) -> Bool {
        guard let call = findCall(uuid: uuid), call.isIncoming, !call.isFinished else { return false }
        if answeredCalls.contains(uuid) { return true }
        answeredCalls.insert(uuid)

        if incomingCall?.id == uuid { incomingCall = nil }
        activeCall = call
        call.state = .connecting

        prepareAudioSession()
        guard let client = makeWebRTCClient(hasVideo: call.hasVideo, isPolite: true) else {
            finish(call, state: .failed, detail: "WebRTC unavailable", callKitReason: nil)
            return false
        }

        signaling.answerCall(callId: call.signalingCallId)

        for candidate in pendingCandidates.removeValue(forKey: call.signalingCallId) ?? [] {
            client.addRemoteCandidate(candidate)
        }
        if let offer = pendingOffers.removeValue(forKey: call.signalingCallId) {
            answer(offer: offer, for: call)
        } else {
            log("Answered before the offer arrived; waiting for it")
        }
        return true
    }

    /// Apply a remote offer and reply. Used for the first exchange and for
    /// renegotiation (the other party turned video on/off mid-call).
    private func answer(offer sdp: String, for call: Call) {
        guard let client = webRTC else { return }
        Task { [weak self] in
            do {
                guard let answer = try await client.handleRemoteOffer(sdp) else { return } // glare: ignored
                guard let self, self.activeCall?.id == call.id, self.webRTC === client else { return }
                self.signaling.sendAnswer(callId: call.signalingCallId, sdp: answer)
            } catch {
                self?.finish(call, state: .failed, detail: "Answer failed: \(error.localizedDescription)", callKitReason: .failed)
            }
        }
    }

    /// Decline the current incoming call.
    func declineCall() {
        guard incomingCall != nil else { return }
        endCall()
    }

    // MARK: Ending calls

    /// End the active call or decline the incoming one (user action).
    func endCall() {
        guard let call = presentedCall ?? calls.values.first(where: { !$0.isFinished }) else { return }
        guard useCallKit else {
            _ = performEndCall(uuid: call.id)
            return
        }
        callKit.requestEndCall(uuid: call.id) { [weak self] error in
            guard let self, error != nil else { return }
            _ = self.performEndCall(uuid: call.id)
        }
    }

    /// Backward-compatible alias.
    func endActiveCall() { endCall() }

    private func performEndCall(uuid: UUID) -> Bool {
        guard let call = findCall(uuid: uuid) else { return true } // already gone
        guard !call.isFinished else { clear(call); return true } // already ended remotely
        if call.isIncoming, !answeredCalls.contains(uuid) {
            log("Declining \(call.signalingCallId)")
            signaling.rejectCall(callId: call.signalingCallId, reason: "declined")
        } else {
            log("Ending \(call.signalingCallId)")
            signaling.endCall(callId: call.signalingCallId)
        }
        finish(call, state: .ended, detail: nil, callKitReason: nil, clearImmediately: true)
        return true
    }

    /// Central teardown. `callKitReason == nil` means CallKit already knows
    /// (the end came through a CXEndCallAction) so nothing is reported.
    private func finish(_ call: Call, state: CallState, detail: String?, callKitReason: CXCallEndedReason?, clearImmediately: Bool = false) {
        guard !call.isFinished else { return }
        ringTimeoutTask?.cancel()
        ringTimeoutTask = nil

        if let reason = callKitReason, useCallKit {
            callKit.reportCallEnded(uuid: call.id, reason: reason)
        }

        teardownMedia()
        call.localVideoTrack = nil
        call.remoteVideoTrack = nil
        pendingOffers.removeValue(forKey: call.signalingCallId)
        pendingCandidates.removeValue(forKey: call.signalingCallId)
        startedCalls.remove(call.id)
        answeredCalls.remove(call.id)
        calls.removeValue(forKey: call.id)

        call.statusDetail = detail
        if state == .failed { call.fail() } else { call.end() }
        log("Call \(call.signalingCallId) \(state == .failed ? "failed" : "ended")\(detail.map { ": \($0)" } ?? "")")

        if clearImmediately {
            clear(call)
        } else {
            // Leave the final state on screen briefly before dismissing.
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(1.5))
                self?.clear(call)
            }
        }
    }

    private func clear(_ call: Call) {
        if incomingCall?.id == call.id { incomingCall = nil }
        if activeCall?.id == call.id { activeCall = nil }
    }

    private func teardownMedia() {
        webRTC?.close()
        webRTC = nil
        #if targetEnvironment(simulator)
        if WebRTCClient.simulatorAudioEnabled { WebRTCClient.activateAudioSession(false) }
        #endif
    }

    // MARK: In-call controls

    func toggleMute() {
        guard let call = activeCall else { return }
        let muted = !call.isMuted
        guard useCallKit else {
            _ = performSetMuted(muted, uuid: call.id)
            return
        }
        callKit.requestSetMuted(uuid: call.id, muted: muted) { [weak self] error in
            guard let self, error != nil else { return }
            _ = self.performSetMuted(muted, uuid: call.id)
        }
    }

    private func performSetMuted(_ muted: Bool, uuid: UUID) -> Bool {
        guard let call = findCall(uuid: uuid) else { return false }
        call.isMuted = muted
        webRTC?.isMuted = muted || call.isOnHold
        return true
    }

    func toggleSpeaker() {
        guard let call = activeCall else { return }
        call.isSpeakerOn.toggle()
        webRTC?.setSpeakerEnabled(call.isSpeakerOn)
    }

    func toggleHold() {
        guard let call = activeCall else { return }
        let onHold = !call.isOnHold
        guard useCallKit else {
            _ = performSetHeld(onHold, uuid: call.id)
            return
        }
        callKit.requestSetHeld(uuid: call.id, onHold: onHold) { [weak self] error in
            guard let self, error != nil else { return }
            _ = self.performSetHeld(onHold, uuid: call.id)
        }
    }

    private func performSetHeld(_ onHold: Bool, uuid: UUID) -> Bool {
        guard let call = findCall(uuid: uuid) else { return false }
        call.isOnHold = onHold
        webRTC?.isMuted = onHold || call.isMuted
        return true
    }

    /// Turn the camera on or off. Works on any call: an audio call becomes a
    /// video call through renegotiation.
    func toggleVideo() {
        guard let call = activeCall, !call.isFinished, let client = webRTC else { return }
        let enable = !call.isVideoEnabled
        log("Video \(enable ? "on" : "off") requested for \(call.signalingCallId)")
        Task { [weak self] in
            if enable {
                let granted = await CallManager.requestCameraPermission()
                guard granted else { self?.log("Camera permission denied"); return }
            }
            guard let self, self.webRTC === client, !call.isFinished else { return }
            do {
                try await client.setVideoEnabled(enable)
                call.isVideoEnabled = enable
                if enable { call.hasVideo = true }
                if self.useCallKit { self.callKit.reportCallUpdated(uuid: call.id, hasVideo: call.hasVideo) }
            } catch {
                self.log("Video toggle failed: \(error.localizedDescription)")
            }
        }
    }

    /// Switch between the front and back camera.
    func flipCamera() {
        guard let call = activeCall, call.isVideoEnabled, let client = webRTC else { return }
        client.switchCamera()
        call.isFrontCamera = (client.cameraPosition == .front)
    }

    /// Camera access. The simulator has no camera (a synthetic source is used)
    /// so no prompt is shown there.
    static func requestCameraPermission() async -> Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return await AVCaptureDevice.requestAccess(for: .video)
        #endif
    }

    func sendDTMF(_ digits: String) {
        guard activeCall?.state == .connected else {
            log("DTMF '\(digits)' ignored: call not connected")
            return
        }
        webRTC?.sendDTMF(digits)
    }

    // MARK: VoIP push

    /// Called from PushKit. Must report an incoming call to CallKit before
    /// `completion` runs (iOS terminates the app otherwise).
    func handleVoIPPush(callId: String?, caller: String?, hasVideo: Bool, completion: @escaping () -> Void) {
        guard let callId, let caller, activeCall == nil, incomingCall == nil else {
            // Report-and-end a placeholder so the push is accounted for.
            let uuid = UUID()
            callKit.reportIncomingCall(uuid: uuid, handle: caller ?? "Unknown", hasVideo: false) { [weak self] _ in
                self?.callKit.reportCallEnded(uuid: uuid, reason: .failed)
                completion()
            }
            return
        }
        // Make sure signaling is up so the offer and candidates can arrive.
        connectSignaling()
        presentIncomingCall(callId: callId, from: caller, hasVideo: hasVideo) {
            completion()
        }
    }

    // MARK: Helpers

    private func makeWebRTCClient(hasVideo: Bool, isPolite: Bool) -> WebRTCClient? {
        webRTC?.close()
        do {
            let client = try WebRTCClient(hasVideo: hasVideo, isPolite: isPolite)
            // Store first: delegate callbacks (the local video track of a
            // video call arrives immediately) are ignored unless client === webRTC.
            webRTC = client
            client.delegate = self
            return client
        } catch {
            log("Failed to create WebRTC client: \(error.localizedDescription)")
            return nil
        }
    }

    private func prepareAudioSession() {
        WebRTCClient.configureAudioSession()
        #if targetEnvironment(simulator)
        // No CallKit-driven activation on the simulator.
        if WebRTCClient.simulatorAudioEnabled { WebRTCClient.activateAudioSession(true) }
        #endif
    }

    private func findCall(uuid: UUID) -> Call? {
        calls[uuid]
    }

    private func findCall(signalingId: String) -> Call? {
        calls.values.first { $0.signalingCallId == signalingId }
    }

    /// The full-screen call UI was dismissed by the user; treat as hang-up.
    func callUIDismissed() {
        guard presentedCall != nil else { return }
        endCall()
    }

    /// The server matches `to` against stored E.164 numbers, so a nationally
    /// dialed number ("5550000002") is converted using the user's own region.
    private func normalizeDialedNumber(_ input: String) -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        var region = PhoneNumberHelper.defaultRegion
        if let own = UserDefaults.standard.string(forKey: Constants.UserDefaults.userPhoneNumber),
           let split = PhoneNumberHelper.split(e164: own) {
            region = split.country.regionCode
        }
        return PhoneNumberHelper.e164(from: trimmed, region: region) ?? trimmed
    }

    private func log(_ message: String) {
        print("📞 [CallManager] \(message)")
    }
}

// MARK: - SignalingClientDelegate

extension CallManager: SignalingClientDelegate {

    func signalingClient(_ client: SignalingClient, didChangeState state: SignalingClient.ConnectionState) {
        log("Signaling state: \(state)")
    }

    func signalingClient(_ client: SignalingClient, didReceiveIncomingCall info: SignalingIncomingCall) {
        guard activeCall == nil, incomingCall == nil else {
            log("Busy; rejecting \(info.callId)")
            signaling.rejectCall(callId: info.callId, reason: "busy")
            return
        }
        presentIncomingCall(callId: info.callId, from: info.from, hasVideo: info.hasVideo)
    }

    func signalingClient(_ client: SignalingClient, didReceiveOffer sdp: String, callId: String, from: String?) {
        guard let call = findCall(signalingId: callId), webRTC != nil,
              answeredCalls.contains(call.id) || startedCalls.contains(call.id) else {
            pendingOffers[callId] = sdp            // ringing; answered later
            return
        }
        // Either the first offer after the user accepted, or a renegotiation
        // (video turned on/off by the other party) on an established call.
        answer(offer: sdp, for: call)
    }

    func signalingClient(_ client: SignalingClient, didReceiveAnswer sdp: String, callId: String, from: String?) {
        guard let call = findCall(signalingId: callId), let webRTC else {
            log("Answer for unknown call \(callId)")
            return
        }
        ringTimeoutTask?.cancel()
        if call.state == .ringing { call.state = .connecting }
        Task { [weak self] in
            do {
                try await webRTC.setRemoteAnswer(sdp)
            } catch {
                self?.finish(call, state: .failed, detail: "Bad answer: \(error.localizedDescription)", callKitReason: .failed)
            }
        }
    }

    func signalingClient(_ client: SignalingClient, didReceiveIceCandidate candidate: SignalingIceCandidate, callId: String) {
        if let call = findCall(signalingId: callId), startedCalls.contains(call.id) || answeredCalls.contains(call.id), let webRTC {
            webRTC.addRemoteCandidate(candidate)
        } else {
            pendingCandidates[callId, default: []].append(candidate)
        }
    }

    func signalingClient(_ client: SignalingClient, callWasAnswered callId: String, by: String?) {
        guard let call = findCall(signalingId: callId) else { return }
        ringTimeoutTask?.cancel()
        if call.state == .ringing { call.state = .connecting }
    }

    func signalingClient(_ client: SignalingClient, callWasRejected callId: String, reason: String?) {
        guard let call = findCall(signalingId: callId) else { return }
        let detail = (reason == "busy") ? "Busy" : "Declined"
        finish(call, state: .ended, detail: detail, callKitReason: .remoteEnded)
    }

    func signalingClient(_ client: SignalingClient, callDidEnd callId: String, reason: String?) {
        guard let call = findCall(signalingId: callId) else { return }
        let detail = (reason == "disconnection") ? "Other party disconnected" : nil
        finish(call, state: .ended, detail: detail, callKitReason: .remoteEnded)
    }

    func signalingClient(_ client: SignalingClient, didReceiveCallError message: String, callId: String?) {
        let call = callId.flatMap { findCall(signalingId: $0) } ?? presentedCall
        guard let call else { return }
        finish(call, state: .failed, detail: message, callKitReason: .failed)
    }
}

// MARK: - WebRTCClientDelegate

extension CallManager: WebRTCClientDelegate {

    func webRTCClient(_ client: WebRTCClient, didGenerateLocalCandidate candidate: SignalingIceCandidate) {
        guard let call = activeCall, client === webRTC else { return }
        signaling.sendIceCandidate(candidate, callId: call.signalingCallId)
    }

    func webRTCClient(_ client: WebRTCClient, didChangeIceConnectionState state: RTCIceConnectionState) {
        guard let call = activeCall, client === webRTC else { return }
        switch state {
        case .connected, .completed:
            if call.state != .connected {
                call.connect()
                if call.isOutgoing, useCallKit { callKit.reportOutgoingCallConnected(uuid: call.id) }
                webRTC?.setSpeakerEnabled(call.isSpeakerOn)
                webRTC?.isMuted = call.isMuted || call.isOnHold
                client.startStatsLogging()
                log("Call \(call.signalingCallId) connected (ICE \(state.name))")
            }
        case .failed:
            finish(call, state: .failed, detail: "Media connection failed", callKitReason: .failed)
        case .disconnected:
            log("ICE disconnected; waiting for recovery")
        default:
            break
        }
    }

    func webRTCClient(_ client: WebRTCClient, didChangePeerConnectionState state: RTCPeerConnectionState) {
        guard let call = activeCall, client === webRTC, state == .failed else { return }
        finish(call, state: .failed, detail: "Peer connection failed", callKitReason: .failed)
    }

    func webRTCClient(_ client: WebRTCClient, didCreateRenegotiationOffer sdp: String) {
        guard let call = activeCall, client === webRTC, !call.isFinished else { return }
        log("Sending renegotiation offer for \(call.signalingCallId)")
        signaling.sendOffer(callId: call.signalingCallId, sdp: sdp)
    }

    func webRTCClient(_ client: WebRTCClient, didChangeLocalVideoTrack track: RTCVideoTrack?) {
        guard let call = activeCall, client === webRTC else { return }
        call.localVideoTrack = track
    }

    func webRTCClient(_ client: WebRTCClient, didChangeRemoteVideoTrack track: RTCVideoTrack?) {
        guard let call = activeCall, client === webRTC else { return }
        call.remoteVideoTrack = track
        log("Remote video \(track == nil ? "off" : "on") for \(call.signalingCallId)")
    }
}

// MARK: - CallKitManagerDelegate

extension CallManager: CallKitManagerDelegate {

    func callKitManager(_ manager: CallKitManager, performStartCall uuid: UUID) -> Bool {
        performStartCall(uuid: uuid)
    }

    func callKitManager(_ manager: CallKitManager, performAnswerCall uuid: UUID) -> Bool {
        performAnswerCall(uuid: uuid)
    }

    func callKitManager(_ manager: CallKitManager, performEndCall uuid: UUID) -> Bool {
        performEndCall(uuid: uuid)
    }

    func callKitManager(_ manager: CallKitManager, performSetMuted muted: Bool, uuid: UUID) -> Bool {
        performSetMuted(muted, uuid: uuid)
    }

    func callKitManager(_ manager: CallKitManager, performSetHeld onHold: Bool, uuid: UUID) -> Bool {
        performSetHeld(onHold, uuid: uuid)
    }

    func callKitManager(_ manager: CallKitManager, performDTMF digits: String, uuid: UUID) -> Bool {
        guard findCall(uuid: uuid) != nil else { return false }
        sendDTMF(digits)
        return true
    }

    func callKitManagerDidReset(_ manager: CallKitManager) {
        if let call = activeCall ?? incomingCall {
            signaling.endCall(callId: call.signalingCallId)
            finish(call, state: .ended, detail: nil, callKitReason: nil, clearImmediately: true)
        }
        teardownMedia()
    }

    func callKitManager(_ manager: CallKitManager, didActivateAudioSession session: AVAudioSession) {
        WebRTCClient.audioSessionDidActivate(session)
    }

    func callKitManager(_ manager: CallKitManager, didDeactivateAudioSession session: AVAudioSession) {
        WebRTCClient.audioSessionDidDeactivate(session)
    }
}

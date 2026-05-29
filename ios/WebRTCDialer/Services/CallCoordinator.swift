//
//  CallCoordinator.swift
//  WebRTCDialer
//
//  Coordinates calls between CallKit, WebRTC, and Signaling
//

import Foundation
import Combine
import CallKit

/// Coordinates all calling functionality
@MainActor
class CallCoordinator: ObservableObject {

    // MARK: - Singleton

    static let shared = CallCoordinator()

    // MARK: - Published Properties

    @Published var activeCall: Call?
    @Published var incomingCall: Call?
    @Published var callState: String = "No active calls"

    // MARK: - Private Properties

    private let callKitManager = CallKitManager.shared
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    private init() {
        setupCallKit()
    }

    // MARK: - Setup

    private func setupCallKit() {
        callKitManager.delegate = self
        print("✅ CallCoordinator initialized")
    }

    // MARK: - Public Methods

    /// Start an outgoing call
    /// - Parameters:
    ///   - phoneNumber: The phone number to call
    ///   - hasVideo: Whether this is a video call
    func startCall(to phoneNumber: String, hasVideo: Bool = false) {
        print("📞 Starting call to: \(phoneNumber)")

        callKitManager.startCall(phoneNumber: phoneNumber, hasVideo: hasVideo) { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success(let call):
                Task { @MainActor in
                    self.activeCall = call
                    self.callState = "Calling \(phoneNumber)..."

                    // TODO: Connect to WebRTC and signaling
                    // For now, simulate connection after delay
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        self.callKitManager.reportOutgoingCallStartedConnecting(call.id)

                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                            self.callKitManager.reportOutgoingCallConnected(call.id)
                            self.callState = "Connected to \(phoneNumber)"
                        }
                    }
                }

            case .failure(let error):
                Task { @MainActor in
                    self.callState = "Failed: \(error.localizedDescription)"
                    print("❌ Failed to start call: \(error)")
                }
            }
        }
    }

    /// Report an incoming call
    /// - Parameters:
    ///   - phoneNumber: The caller's phone number
    ///   - hasVideo: Whether this is a video call
    ///   - callId: The call UUID from signaling server
    func reportIncomingCall(from phoneNumber: String, hasVideo: Bool = false, callId: UUID) {
        print("📲 Incoming call from: \(phoneNumber)")

        callKitManager.reportIncomingCall(phoneNumber: phoneNumber, hasVideo: hasVideo, callId: callId) { [weak self] error in
            guard let self = self else { return }

            if let error = error {
                print("❌ Failed to report incoming call: \(error)")
                Task { @MainActor in
                    self.callState = "Failed to show incoming call"
                }
            } else {
                Task { @MainActor in
                    if let call = self.callKitManager.getCall(callId) {
                        self.incomingCall = call
                        self.callState = "Incoming call from \(phoneNumber)"
                    }
                }
            }
        }
    }

    /// Answer the current incoming call
    func answerCall() {
        guard let call = incomingCall else {
            print("⚠️ No incoming call to answer")
            return
        }

        print("✅ Answering call from: \(call.phoneNumber)")

        callKitManager.answerCall(call.id) { [weak self] error in
            guard let self = self else { return }

            if let error = error {
                print("❌ Failed to answer call: \(error)")
            } else {
                Task { @MainActor in
                    self.activeCall = call
                    self.incomingCall = nil
                    self.callState = "Connected to \(call.phoneNumber)"

                    // TODO: Connect WebRTC media streams
                }
            }
        }
    }

    /// End the active call
    func endCall() {
        guard let call = activeCall ?? incomingCall else {
            print("⚠️ No active call to end")
            return
        }

        print("📴 Ending call: \(call.phoneNumber)")

        callKitManager.endCall(call.id) { [weak self] error in
            guard let self = self else { return }

            if let error = error {
                print("❌ Failed to end call: \(error)")
            } else {
                Task { @MainActor in
                    self.activeCall = nil
                    self.incomingCall = nil
                    self.callState = "Call ended"

                    // TODO: Cleanup WebRTC and signaling connections
                }
            }
        }
    }

    /// Toggle mute
    func toggleMute() {
        guard let call = activeCall else { return }

        let newMuteState = !call.isMuted

        callKitManager.setMuted(call.id, muted: newMuteState) { error in
            if let error = error {
                print("❌ Failed to toggle mute: \(error)")
            } else {
                print("🔇 Mute: \(newMuteState)")
                // The delegate will update the call object
            }
        }
    }

    /// Toggle hold
    func toggleHold() {
        guard let call = activeCall else { return }

        let newHoldState = !call.isOnHold

        callKitManager.setHold(call.id, onHold: newHoldState) { error in
            if let error = error {
                print("❌ Failed to toggle hold: \(error)")
            } else {
                print("⏸️ Hold: \(newHoldState)")
                // The delegate will update the call object
            }
        }
    }

    /// Toggle speaker
    func toggleSpeaker() {
        guard let call = activeCall else { return }

        Task { @MainActor in
            call.isSpeakerOn.toggle()
            print("🔊 Speaker: \(call.isSpeakerOn)")

            // TODO: Update audio route for WebRTC
        }
    }

    /// Toggle video (for video calls)
    func toggleVideo() {
        guard let call = activeCall, call.hasVideo else { return }

        Task { @MainActor in
            call.isVideoEnabled.toggle()
            print("📹 Video: \(call.isVideoEnabled)")

            // TODO: Enable/disable WebRTC video track
        }
    }
}

// MARK: - CallKitManagerDelegate

extension CallCoordinator: CallKitManagerDelegate {

    func callKitManager(_ manager: CallKitManager, didStartCall call: Call) {
        print("📞 CallKit: Did start call to \(call.phoneNumber)")

        Task { @MainActor in
            activeCall = call
            callState = "Calling \(call.phoneNumber)..."

            // TODO: Initiate WebRTC connection
            // TODO: Send call-initiate to signaling server
        }
    }

    func callKitManager(_ manager: CallKitManager, didAnswerCall call: Call) {
        print("✅ CallKit: Did answer call from \(call.phoneNumber)")

        Task { @MainActor in
            activeCall = call
            incomingCall = nil
            callState = "Connected to \(call.phoneNumber)"

            // TODO: Answer WebRTC connection
            // TODO: Send call-answer to signaling server
        }
    }

    func callKitManager(_ manager: CallKitManager, didEndCall call: Call) {
        print("📴 CallKit: Did end call with \(call.phoneNumber)")

        Task { @MainActor in
            activeCall = nil
            incomingCall = nil
            callState = "Call ended"

            // TODO: Close WebRTC connection
            // TODO: Send call-end to signaling server
        }
    }

    func callKitManager(_ manager: CallKitManager, didHoldCall call: Call, onHold: Bool) {
        print("⏸️ CallKit: Did change hold state to \(onHold)")

        Task { @MainActor in
            call.isOnHold = onHold
            callState = onHold ? "Call on hold" : "Connected to \(call.phoneNumber)"

            // TODO: Pause/resume WebRTC media
        }
    }

    func callKitManager(_ manager: CallKitManager, didMuteCall call: Call, muted: Bool) {
        print("🔇 CallKit: Did change mute state to \(muted)")

        Task { @MainActor in
            call.isMuted = muted

            // TODO: Mute/unmute WebRTC audio track
        }
    }
}

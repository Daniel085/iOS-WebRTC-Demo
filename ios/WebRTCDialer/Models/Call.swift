//
//  Call.swift
//  WebRTCDialer
//
//  Created by Claude Code
//

import Foundation
import SwiftUI
import Combine

/// Represents a call session
class Call: Identifiable, ObservableObject {
    let id: UUID
    let phoneNumber: String

    /// Whether this is a video call
    var hasVideo: Bool

    /// Whether this is an incoming call (vs outgoing)
    let isIncoming: Bool

    /// Convenience computed property
    var isOutgoing: Bool { !isIncoming }

    /// Current call state
    @Published var state: CallState = .idle

    /// Whether audio is muted
    @Published var isMuted: Bool = false

    /// Whether speaker is enabled
    @Published var isSpeakerOn: Bool = true

    /// Whether call is on hold
    @Published var isOnHold: Bool = false

    /// Whether video is currently enabled
    @Published var isVideoEnabled: Bool

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
        phoneNumber: String,
        isIncoming: Bool = false,
        hasVideo: Bool = false,
        state: CallState = .idle
    ) {
        self.id = id
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

/// Call manager to handle active calls
@MainActor
class CallManager: ObservableObject {
    static let shared = CallManager()

    @Published var activeCall: Call?
    @Published var incomingCall: Call?

    private init() {}

    /// Initiate an outgoing call
    func startCall(to phoneNumber: String, isVideo: Bool) {
        let call = Call(phoneNumber: phoneNumber, isVideo: isVideo, isOutgoing: true)
        call.start()
        activeCall = call

        // Simulate connection after a delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            call.connect()
        }
    }

    /// Receive an incoming call
    func receiveCall(from phoneNumber: String, isVideo: Bool) {
        let call = Call(phoneNumber: phoneNumber, isVideo: isVideo, isOutgoing: false)
        call.start()
        incomingCall = call
    }

    /// Accept an incoming call
    func acceptCall() {
        guard let call = incomingCall else { return }
        call.connect()
        activeCall = call
        incomingCall = nil
    }

    /// Decline an incoming call
    func declineCall() {
        incomingCall?.end()
        incomingCall = nil
    }

    /// End the active call
    func endActiveCall() {
        activeCall?.end()
        activeCall = nil
    }
}

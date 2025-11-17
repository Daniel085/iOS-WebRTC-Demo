//
//  Call.swift
//  WebRTCDialer
//
//  Created by Claude Code
//

import Foundation

/// Represents a call session
class Call: Identifiable {
    let id: UUID
    let phoneNumber: String
    let isVideo: Bool
    let isOutgoing: Bool
    var connectedAt: Date?
    var endedAt: Date?
    var duration: TimeInterval {
        guard let connectedAt = connectedAt else { return 0 }
        let endTime = endedAt ?? Date()
        return endTime.timeIntervalSince(connectedAt)
    }

    init(id: UUID = UUID(), phoneNumber: String, isVideo: Bool, isOutgoing: Bool = true) {
        self.id = id
        self.phoneNumber = phoneNumber
        self.isVideo = isVideo
        self.isOutgoing = isOutgoing
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

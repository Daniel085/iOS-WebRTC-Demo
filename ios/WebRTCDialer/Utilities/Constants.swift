//
//  Constants.swift
//  WebRTCDialer
//
//  Created by Claude Code
//

import Foundation

enum Constants {
    /// API Configuration
    enum API {
        static let baseURL = "http://localhost:3000" // Local development server
        static let signalingURL = "ws://localhost:3001" // Local WebSocket server
    }

    /// STUN/TURN Servers
    enum ICE {
        static let stunServers = [
            "stun:stun.l.google.com:19302",
            "stun:stun1.l.google.com:19302"
        ]

        // Replace with your TURN server credentials
        static let turnServer = "turn:your-turn-server.com:3478"
        static let turnUsername = "username"
        static let turnPassword = "password"
    }

    /// Keychain Keys
    enum Keychain {
        static let authToken = "authToken"
        static let refreshToken = "refreshToken"
    }

    /// UserDefaults Keys
    enum UserDefaults {
        static let userPhoneNumber = "userPhoneNumber"
        static let voipDeviceToken = "voipDeviceToken"
    }

    /// VoIP Configuration
    enum VoIP {
        static let bundleID = "com.yourcompany.webrtcdialer" // Replace with your bundle ID
        static let voipSuffix = ".voip"
    }
}

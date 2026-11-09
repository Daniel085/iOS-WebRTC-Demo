//
//  Constants.swift
//  WebRTCDialer
//
//  Created by Claude Code
//

import Foundation

enum Constants {
    /// API Configuration
    ///
    /// The backend serves the REST API and the Socket.IO signaling endpoint on a
    /// single port, so one base URL covers both. The effective URL can be changed
    /// at runtime from Settings → Server (stored in UserDefaults); otherwise the
    /// build default below is used.
    enum API {
        /// Default used when no override has been saved in Settings.
        /// - Simulator: the backend running on this Mac.
        /// - Device: the Mac's LAN address (edit for your network) until a
        ///   hosted backend URL is configured.
        static var defaultBaseURL: String {
            #if targetEnvironment(simulator)
            return "http://localhost:3000"
            #else
            return "http://192.168.4.20:3000"
            #endif
        }

        /// Effective REST base URL (runtime override or build default).
        static var baseURL: String {
            let saved = Foundation.UserDefaults.standard.string(forKey: Constants.UserDefaults.serverBaseURL)
            let trimmed = saved?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let url = trimmed.isEmpty ? defaultBaseURL : trimmed
            return url.hasSuffix("/") ? String(url.dropLast()) : url
        }

        /// Signaling (Socket.IO) URL. Same host and port as the REST API;
        /// http(s) is translated to ws(s).
        static var signalingURL: String {
            var url = baseURL
            if url.hasPrefix("https://") {
                url = "wss://" + url.dropFirst("https://".count)
            } else if url.hasPrefix("http://") {
                url = "ws://" + url.dropFirst("http://".count)
            }
            return url
        }
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
        static let serverBaseURL = "serverBaseURL"
        /// Simulator only: start WebRTC's audio unit (off by default, see WebRTCClient.initialize).
        static let simulatorAudioEnabled = "simulatorAudioEnabled"
        /// Use WebRTC's built-in audio unit instead of EngineAudioDevice
        /// (disables transcription). Read at launch.
        static let useBuiltInWebRTCAudio = "useBuiltInWebRTCAudio"
        /// Simulator/testing: feed synthesized speech to the transcriber instead
        /// of the microphone (the simulator normally runs with audio off).
        static let transcriptionDemoAudio = "transcriptionDemoAudio"
    }

    /// VoIP Configuration
    enum VoIP {
        static let bundleID = "com.D3DigitalProductions.WebRTCDialer"
        static let voipSuffix = ".voip"
    }
}

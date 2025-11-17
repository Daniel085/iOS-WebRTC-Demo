//
//  WebRTCDialerApp.swift
//  WebRTCDialer
//
//  Created by Daniel O'Rorke on 11/14/25.
//

import SwiftUI
import Combine

@main
struct WebRTCDialerApp: App {
    @StateObject private var appState = AppState()

    init() {
        // Initialize WebRTC on app launch
        // RTCInitializeSSL() will be called in WebRTCClient when implemented
    }

    var body: some Scene {
        WindowGroup {
            if appState.isAuthenticated {
                MainTabView()
                    .environmentObject(appState)
            } else {
                AuthenticationView()
                    .environmentObject(appState)
            }
        }
    }
}

/// App-wide state management
class AppState: ObservableObject {
    @Published var isAuthenticated = false

    init() {
        // Check if user is authenticated
        isAuthenticated = AuthenticationService.shared.isAuthenticated
    }

    func login() {
        isAuthenticated = true
    }

    func logout() {
        AuthenticationService.shared.logout()
        isAuthenticated = false
    }
}

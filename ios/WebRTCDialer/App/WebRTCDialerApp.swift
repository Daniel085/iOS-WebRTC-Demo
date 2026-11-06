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
        // Initializes the WebRTC factory/SSL, the CallKit provider and PushKit
        // before any UI so incoming calls can be handled from launch.
        CallManager.shared.bootstrap()
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
@MainActor
class AppState: ObservableObject {
    @Published var isAuthenticated = false

    init() {
        // Check if user is authenticated
        isAuthenticated = AuthenticationService.shared.isAuthenticated
        if isAuthenticated {
            CallManager.shared.connectSignaling()
        }
    }

    func login() {
        isAuthenticated = true
        CallManager.shared.connectSignaling()
    }

    func logout() {
        CallManager.shared.disconnectSignaling()
        AuthenticationService.shared.logout()
        isAuthenticated = false
    }
}

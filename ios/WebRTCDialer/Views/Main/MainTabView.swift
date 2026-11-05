//
//  MainTabView.swift
//  WebRTCDialer
//
//  Created by Claude Code
//

import SwiftUI

struct MainTabView: View {
    @State private var selectedTab = 1
    @StateObject private var callManager = CallManager.shared

    var body: some View {
        TabView(selection: $selectedTab) {
            RecentsView()
                .tabItem {
                    Label("Recents", systemImage: "clock.fill")
                }
                .tag(0)

            ContactsView()
                .tabItem {
                    Label("Contacts", systemImage: "person.crop.circle.fill")
                }
                .tag(1)

            KeypadView()
                .tabItem {
                    Label("Keypad", systemImage: "dial.fill")
                }
                .tag(2)

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
                .tag(3)
        }
        // Hosted here (not in KeypadView) so a call is shown whichever tab is
        // active. One cover for both phases, so accepting an incoming call
        // swaps to the active screen in place instead of re-presenting.
        .fullScreenCover(item: presentedCall) { call in
            CallScreen(call: call)
        }
    }

    private var presentedCall: Binding<Call?> {
        Binding(
            get: { callManager.presentedCall },
            set: { if $0 == nil { callManager.callUIDismissed() } }
        )
    }
}

/// Shows the incoming-call screen while a call is ringing in, then the
/// active-call screen once it is accepted (or for outgoing calls).
struct CallScreen: View {
    @ObservedObject var call: Call

    var body: some View {
        if call.isIncoming && call.state == .ringing {
            IncomingCallView(call: call)
        } else {
            ActiveCallView(call: call)
        }
    }
}

#Preview {
    MainTabView()
        .environmentObject(AppState())
}

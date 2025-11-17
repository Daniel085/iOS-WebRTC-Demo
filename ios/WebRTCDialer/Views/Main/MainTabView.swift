//
//  MainTabView.swift
//  WebRTCDialer
//
//  Created by Claude Code
//

import SwiftUI

struct MainTabView: View {
    @State private var selectedTab = 1

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
    }
}

#Preview {
    MainTabView()
        .environmentObject(AppState())
}

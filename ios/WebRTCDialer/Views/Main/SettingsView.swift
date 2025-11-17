//
//  SettingsView.swift
//  WebRTCDialer
//
//  Created by Claude Code
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var phoneNumber = UserDefaults.standard.string(forKey: Constants.UserDefaults.userPhoneNumber) ?? "Not set"

    var body: some View {
        NavigationView {
            List {
                // Account Section
                Section("Account") {
                    HStack {
                        Text("Phone Number")
                        Spacer()
                        Text(phoneNumber)
                            .foregroundColor(.gray)
                    }
                }

                // Call Settings
                Section("Call Settings") {
                    NavigationLink(destination: Text("Audio Settings")) {
                        Label("Audio", systemImage: "speaker.wave.2")
                    }

                    NavigationLink(destination: Text("Video Settings")) {
                        Label("Video", systemImage: "video")
                    }

                    NavigationLink(destination: Text("Network Settings")) {
                        Label("Network", systemImage: "network")
                    }
                }

                // Privacy & Permissions
                Section("Privacy") {
                    NavigationLink(destination: Text("Blocked Contacts")) {
                        Label("Blocked Contacts", systemImage: "hand.raised")
                    }

                    NavigationLink(destination: Text("Permissions")) {
                        Label("Permissions", systemImage: "lock.shield")
                    }
                }

                // About
                Section("About") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(.gray)
                    }

                    NavigationLink(destination: Text("Privacy Policy")) {
                        Text("Privacy Policy")
                    }

                    NavigationLink(destination: Text("Terms of Service")) {
                        Text("Terms of Service")
                    }
                }

                // Logout
                Section {
                    Button(action: {
                        appState.logout()
                    }) {
                        HStack {
                            Spacer()
                            Text("Logout")
                                .foregroundColor(.red)
                            Spacer()
                        }
                    }
                }
            }
            .navigationTitle("Settings")
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(AppState())
}

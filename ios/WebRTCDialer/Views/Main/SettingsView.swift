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
    @State private var serverURL = UserDefaults.standard.string(forKey: Constants.UserDefaults.serverBaseURL) ?? ""
    @State private var serverStatus: ServerStatus = .unknown

    enum ServerStatus: Equatable {
        case unknown
        case checking
        case reachable(String)
        case unreachable(String)
    }

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

                // Server
                Section {
                    TextField(Constants.API.defaultBaseURL, text: $serverURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onSubmit(saveServerURL)

                    HStack {
                        Button("Save") { saveServerURL() }
                        Spacer()
                        Button("Test Connection") { testConnection() }
                            .disabled(serverStatus == .checking)
                    }

                    HStack {
                        Text("Status")
                        Spacer()
                        switch serverStatus {
                        case .unknown:
                            Text("Not tested").foregroundColor(.gray)
                        case .checking:
                            ProgressView()
                        case .reachable(let detail):
                            Text(detail).foregroundColor(.green)
                        case .unreachable(let detail):
                            Text(detail).foregroundColor(.red)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                } header: {
                    Text("Server")
                } footer: {
                    Text("REST API and call signaling share this address. Leave blank to use the default: \(Constants.API.defaultBaseURL)")
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

    private func saveServerURL() {
        let trimmed = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            UserDefaults.standard.removeObject(forKey: Constants.UserDefaults.serverBaseURL)
        } else {
            UserDefaults.standard.set(trimmed, forKey: Constants.UserDefaults.serverBaseURL)
        }
        serverURL = trimmed
        serverStatus = .unknown
    }

    private func testConnection() {
        saveServerURL()
        guard let url = URL(string: "\(Constants.API.baseURL)/health") else {
            serverStatus = .unreachable("Invalid URL")
            return
        }
        serverStatus = .checking
        Task {
            do {
                var request = URLRequest(url: url)
                request.timeoutInterval = 8
                let (data, response) = try await URLSession.shared.data(for: request)
                let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                if code == 200,
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let status = json["status"] as? String {
                    let env = json["environment"] as? String ?? ""
                    serverStatus = .reachable(env.isEmpty ? status : "\(status) (\(env))")
                } else {
                    serverStatus = .unreachable("HTTP \(code)")
                }
            } catch {
                serverStatus = .unreachable(error.localizedDescription)
            }
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(AppState())
}

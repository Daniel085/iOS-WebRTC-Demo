//
//  RecentsView.swift
//  WebRTCDialer
//
//  Created by Claude Code
//

import SwiftUI

struct RecentsView: View {
    @State private var recentCalls: [RecentCall] = []

    var body: some View {
        NavigationView {
            if recentCalls.isEmpty {
                VStack(spacing: 20) {
                    Image(systemName: "phone.circle")
                        .resizable()
                        .frame(width: 80, height: 80)
                        .foregroundColor(.gray)

                    Text("No Recent Calls")
                        .font(.title2)
                        .foregroundColor(.gray)

                    Text("Your call history will appear here")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                }
                .navigationTitle("Recents")
            } else {
                List(recentCalls) { call in
                    RecentCallRow(call: call)
                }
                .navigationTitle("Recents")
            }
        }
    }
}

struct RecentCallRow: View {
    let call: RecentCall

    var body: some View {
        HStack {
            // Call type icon
            Image(systemName: call.isVideo ? "video.fill" : "phone.fill")
                .foregroundColor(call.isMissed ? .red : .gray)
                .frame(width: 30)

            VStack(alignment: .leading) {
                Text(call.phoneNumber)
                    .font(.body)

                HStack(spacing: 5) {
                    if call.isMissed {
                        Text("Missed")
                            .foregroundColor(.red)
                    } else if call.isOutgoing {
                        Image(systemName: "phone.arrow.up.right")
                    } else {
                        Image(systemName: "phone.arrow.down.left")
                    }

                    Text(call.timestamp, style: .relative)
                }
                .font(.caption)
                .foregroundColor(.gray)
            }

            Spacer()

            // Info button
            Button(action: {
                // Show call details
            }) {
                Image(systemName: "info.circle")
                    .foregroundColor(.blue)
            }
        }
        .padding(.vertical, 5)
    }
}

struct RecentCall: Identifiable {
    let id = UUID()
    let phoneNumber: String
    let isVideo: Bool
    let isOutgoing: Bool
    let isMissed: Bool
    let timestamp: Date
}

#Preview {
    RecentsView()
}

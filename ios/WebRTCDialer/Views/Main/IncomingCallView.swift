//
//  IncomingCallView.swift
//  WebRTCDialer
//
//  Created by Claude Code
//

import SwiftUI
import Combine

struct IncomingCallView: View {
    @StateObject private var viewModel: IncomingCallViewModel
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme

    init(call: Call) {
        _viewModel = StateObject(wrappedValue: IncomingCallViewModel(call: call))
    }

    var body: some View {
        ZStack {
            // Background with gradient
            LinearGradient(
                gradient: Gradient(colors: [
                    Color.black.opacity(0.9),
                    Color.black
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()
                    .frame(height: 100)

                // Caller info section
                VStack(spacing: 20) {
                    // Profile image placeholder
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    gradient: Gradient(colors: [Color.blue.opacity(0.6), Color.blue]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 140, height: 140)

                        Text(viewModel.initials)
                            .font(.system(size: 56, weight: .light))
                            .foregroundColor(.white)
                    }
                    .padding(.bottom, 30)

                    // Caller name/number
                    Text(viewModel.displayName)
                        .font(.system(size: 36, weight: .light))
                        .foregroundColor(.white)

                    // Call type indicator
                    HStack(spacing: 8) {
                        Image(systemName: viewModel.call.isVideo ? "video.fill" : "phone.fill")
                            .font(.system(size: 14))

                        Text(viewModel.call.isVideo ? "FaceTime Video" : "iPhone")
                            .font(.system(size: 17))
                    }
                    .foregroundColor(.white.opacity(0.8))
                    .padding(.top, 8)
                }
                .padding(.top, 60)

                Spacer()

                // Quick action buttons
                VStack(spacing: 24) {
                    // Remind Me button
                    IncomingCallActionButton(
                        icon: "clock.fill",
                        label: "Remind Me"
                    ) {
                        viewModel.remindMe()
                    }

                    // Message button
                    IncomingCallActionButton(
                        icon: "message.fill",
                        label: "Message"
                    ) {
                        viewModel.sendMessage()
                    }
                }
                .padding(.horizontal, 60)
                .padding(.bottom, 60)

                // Answer/Decline buttons
                HStack(spacing: 80) {
                    // Decline button
                    VStack(spacing: 12) {
                        Button(action: {
                            viewModel.declineCall()
                            dismiss()
                        }) {
                            ZStack {
                                Circle()
                                    .fill(Color.red)
                                    .frame(width: 75, height: 75)

                                Image(systemName: "phone.down.fill")
                                    .font(.system(size: 28, weight: .medium))
                                    .foregroundColor(.white)
                            }
                        }
                        .buttonStyle(ScaleButtonStyle())

                        Text("Decline")
                            .font(.system(size: 13))
                            .foregroundColor(.white.opacity(0.8))
                    }

                    // Accept button
                    VStack(spacing: 12) {
                        Button(action: {
                            viewModel.acceptCall()
                            dismiss()
                        }) {
                            ZStack {
                                Circle()
                                    .fill(Color.green)
                                    .frame(width: 75, height: 75)

                                Image(systemName: "phone.fill")
                                    .font(.system(size: 28, weight: .medium))
                                    .foregroundColor(.white)
                            }
                        }
                        .buttonStyle(ScaleButtonStyle())

                        Text("Accept")
                            .font(.system(size: 13))
                            .foregroundColor(.white.opacity(0.8))
                    }
                }
                .padding(.bottom, 60)
            }
        }
        .navigationBarHidden(true)
    }
}

struct IncomingCallActionButton: View {
    let icon: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundColor(.white)
                    .frame(width: 30)

                Text(label)
                    .font(.system(size: 20))
                    .foregroundColor(.white)

                Spacer()
            }
            .padding(.vertical, 16)
            .padding(.horizontal, 24)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.15))
            )
        }
        .buttonStyle(ScaleButtonStyle())
    }
}

@MainActor
class IncomingCallViewModel: ObservableObject {
    let call: Call
    private let callManager = CallManager.shared

    var displayName: String {
        call.phoneNumber
    }

    var initials: String {
        if let first = call.phoneNumber.first {
            return String(first)
        }
        return "?"
    }

    init(call: Call) {
        self.call = call
    }

    func acceptCall() {
        callManager.acceptCall()
    }

    func declineCall() {
        callManager.declineCall()
    }

    func remindMe() {
        // TODO: Implement remind me functionality
        print("Remind me tapped")
        declineCall()
    }

    func sendMessage() {
        // TODO: Implement send message functionality
        print("Send message tapped")
        declineCall()
    }
}

#Preview {
    IncomingCallView(call: Call(phoneNumber: "+1 (555) 123-4567", isVideo: false, isOutgoing: false))
}

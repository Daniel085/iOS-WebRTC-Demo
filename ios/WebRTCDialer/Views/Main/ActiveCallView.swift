//
//  ActiveCallView.swift
//  WebRTCDialer
//
//  Created by Claude Code
//

import SwiftUI

struct ActiveCallView: View {
    @StateObject private var viewModel: ActiveCallViewModel
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme

    init(call: Call) {
        _viewModel = StateObject(wrappedValue: ActiveCallViewModel(call: call))
    }

    var body: some View {
        ZStack {
            // Background
            (colorScheme == .dark ? Color.black : Color(white: 0.95))
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()
                    .frame(height: 80)

                // Caller info section
                VStack(spacing: 12) {
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
                            .frame(width: 120, height: 120)

                        Text(viewModel.initials)
                            .font(.system(size: 48, weight: .light))
                            .foregroundColor(.white)
                    }
                    .padding(.bottom, 20)

                    // Caller name/number
                    Text(viewModel.displayName)
                        .font(.system(size: 34, weight: .light))
                        .foregroundColor(.primary)

                    // Call status
                    Text(viewModel.callStatusText)
                        .font(.system(size: 17))
                        .foregroundColor(.secondary)
                        .padding(.top, 4)
                }
                .padding(.top, 40)

                Spacer()

                // Call control buttons
                VStack(spacing: 24) {
                    // First row: mute, keypad, speaker
                    HStack(spacing: 60) {
                        CallControlButton(
                            icon: viewModel.isMuted ? "mic.slash.fill" : "mic.fill",
                            label: "mute",
                            isActive: viewModel.isMuted,
                            action: { viewModel.toggleMute() }
                        )

                        CallControlButton(
                            icon: "dial.medium.fill",
                            label: "keypad",
                            isActive: viewModel.showKeypad,
                            action: { viewModel.toggleKeypad() }
                        )

                        CallControlButton(
                            icon: "speaker.wave.3.fill",
                            label: "speaker",
                            isActive: viewModel.isSpeakerOn,
                            action: { viewModel.toggleSpeaker() }
                        )
                    }

                    // Second row: add call, video, contacts
                    HStack(spacing: 60) {
                        CallControlButton(
                            icon: "plus",
                            label: "add call",
                            isActive: false,
                            action: { viewModel.addCall() }
                        )

                        CallControlButton(
                            icon: viewModel.isVideoEnabled ? "video.fill" : "video.slash.fill",
                            label: "video",
                            isActive: viewModel.isVideoEnabled,
                            action: { viewModel.toggleVideo() }
                        )

                        CallControlButton(
                            icon: "person.crop.circle.fill",
                            label: "contacts",
                            isActive: false,
                            action: { viewModel.showContacts() }
                        )
                    }
                }
                .padding(.horizontal, 40)
                .padding(.bottom, 40)

                // End call button
                Button(action: {
                    viewModel.endCall()
                    dismiss()
                }) {
                    Image(systemName: "phone.down.fill")
                        .font(.system(size: 28, weight: .medium))
                        .foregroundColor(.white)
                        .frame(width: 75, height: 75)
                        .background(
                            Circle()
                                .fill(Color.red)
                        )
                }
                .padding(.bottom, 50)
            }

            // Keypad overlay
            if viewModel.showKeypad {
                VStack {
                    Spacer()
                    InCallKeypadView(viewModel: viewModel)
                        .transition(.move(edge: .bottom))
                }
                .background(
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                        .onTapGesture {
                            withAnimation {
                                viewModel.showKeypad = false
                            }
                        }
                )
            }
        }
        .navigationBarHidden(true)
    }
}

struct CallControlButton: View {
    let icon: String
    let label: String
    let isActive: Bool
    let action: () -> Void

    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(isActive ? Color.white : (colorScheme == .dark ? Color(white: 0.2) : Color(white: 0.85)))
                        .frame(width: 68, height: 68)

                    Image(systemName: icon)
                        .font(.system(size: 24))
                        .foregroundColor(isActive ? .black : .white)
                }

                Text(label)
                    .font(.system(size: 13))
                    .foregroundColor(.white)
            }
        }
        .buttonStyle(ScaleButtonStyle())
    }
}

struct InCallKeypadView: View {
    @ObservedObject var viewModel: ActiveCallViewModel
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            // Keypad background
            RoundedRectangle(cornerRadius: 20)
                .fill(colorScheme == .dark ? Color(white: 0.15) : Color.white)
                .frame(height: 500)
                .overlay(
                    VStack(spacing: 16) {
                        // DTMF display
                        Text(viewModel.dtmfDigits)
                            .font(.system(size: 24, weight: .light))
                            .foregroundColor(.primary)
                            .frame(height: 40)
                            .padding(.top, 20)

                        // Keypad grid
                        VStack(spacing: 12) {
                            ForEach(0..<4) { row in
                                HStack(spacing: 35) {
                                    ForEach(0..<3) { col in
                                        if row == 3 {
                                            if col == 0 {
                                                DTMFButton(title: "*", subtitle: "") {
                                                    viewModel.sendDTMF("*")
                                                }
                                            } else if col == 1 {
                                                DTMFButton(title: "0", subtitle: "+") {
                                                    viewModel.sendDTMF("0")
                                                }
                                            } else {
                                                DTMFButton(title: "#", subtitle: "") {
                                                    viewModel.sendDTMF("#")
                                                }
                                            }
                                        } else {
                                            let index = row * 3 + col
                                            if index < 9 {
                                                DTMFButton(
                                                    title: "\(index + 1)",
                                                    subtitle: getLetters(for: index + 1)
                                                ) {
                                                    viewModel.sendDTMF("\(index + 1)")
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // Hide keypad button
                        Button(action: {
                            withAnimation {
                                viewModel.showKeypad = false
                            }
                        }) {
                            Text("Hide")
                                .font(.system(size: 17))
                                .foregroundColor(.blue)
                                .padding(.top, 20)
                        }
                    }
                )
                .padding(.horizontal, 20)
        }
    }

    private func getLetters(for digit: Int) -> String {
        switch digit {
        case 2: return "ABC"
        case 3: return "DEF"
        case 4: return "GHI"
        case 5: return "JKL"
        case 6: return "MNO"
        case 7: return "PQRS"
        case 8: return "TUV"
        case 9: return "WXYZ"
        default: return ""
        }
    }
}

struct DTMFButton: View {
    let title: String
    let subtitle: String
    let action: () -> Void

    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        Button(action: action) {
            VStack(spacing: -2) {
                Text(title)
                    .font(.system(size: 32, weight: .light))
                    .foregroundColor(.primary)

                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.primary)
                        .opacity(0.5)
                        .tracking(1.5)
                }
            }
            .frame(width: 70, height: 70)
            .background(
                Circle()
                    .fill(colorScheme == .dark ? Color(white: 0.25) : Color(white: 0.95))
            )
        }
        .buttonStyle(ScaleButtonStyle())
    }
}

struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : 1.0)
            .opacity(configuration.isPressed ? 0.7 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

@MainActor
class ActiveCallViewModel: ObservableObject {
    @Published var isMuted = false
    @Published var isSpeakerOn = true
    @Published var isVideoEnabled: Bool
    @Published var showKeypad = false
    @Published var dtmfDigits = ""
    @Published var callDuration: TimeInterval = 0

    private let call: Call
    private let callManager = CallManager.shared
    private var timer: Timer?

    var displayName: String {
        call.phoneNumber
    }

    var initials: String {
        if let first = call.phoneNumber.first {
            return String(first)
        }
        return "?"
    }

    var callStatusText: String {
        if call.state == .connected && callDuration > 0 {
            return formatDuration(callDuration)
        }
        return call.state.description
    }

    init(call: Call) {
        self.call = call
        self.isVideoEnabled = call.isVideo

        // Start call timer when connected
        if call.state == .connected {
            startTimer()
        }
    }

    deinit {
        timer?.invalidate()
    }

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.callDuration += 1
        }
    }

    func toggleMute() {
        isMuted.toggle()
        call.isMuted = isMuted
        // TODO: Implement actual mute functionality
    }

    func toggleSpeaker() {
        isSpeakerOn.toggle()
        call.isSpeakerOn = isSpeakerOn
        // TODO: Implement actual speaker toggle
    }

    func toggleVideo() {
        isVideoEnabled.toggle()
        call.isVideoEnabled = isVideoEnabled
        // TODO: Implement actual video toggle
    }

    func toggleKeypad() {
        withAnimation {
            showKeypad.toggle()
        }
    }

    func addCall() {
        // TODO: Implement add call functionality
        print("Add call tapped")
    }

    func showContacts() {
        // TODO: Implement show contacts
        print("Show contacts tapped")
    }

    func sendDTMF(_ digit: String) {
        dtmfDigits += digit
        // TODO: Send actual DTMF tone
        print("DTMF: \(digit)")
    }

    func endCall() {
        timer?.invalidate()
        callManager.endActiveCall()
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = Int(duration) / 60 % 60
        let seconds = Int(duration) % 60

        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }
}

#Preview {
    ActiveCallView(call: Call(phoneNumber: "+1 (555) 123-4567", isVideo: false))
}

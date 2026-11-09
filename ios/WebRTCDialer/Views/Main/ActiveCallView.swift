//
//  ActiveCallView.swift
//  WebRTCDialer
//
//  Created by Claude Code
//

import SwiftUI
import Combine

struct ActiveCallView: View {
    @StateObject private var viewModel: ActiveCallViewModel
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
                    .frame(height: viewModel.showCaptions ? 16 : 80)

                // Caller info section
                VStack(spacing: 12) {
                    // Profile image placeholder (hidden to make room for captions)
                    if !viewModel.showCaptions {
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
                    }

                    // Caller name/number
                    Text(viewModel.displayName)
                        .font(.system(size: viewModel.showCaptions ? 26 : 34, weight: .light))
                        .foregroundColor(.primary)

                    // Call status
                    Text(viewModel.callStatusText)
                        .font(.system(size: 17))
                        .foregroundColor(.secondary)
                        .padding(.top, 4)

                    TranscriptionStatusView(transcription: viewModel.transcription)
                }
                .padding(.top, viewModel.showCaptions ? 8 : 40)

                if viewModel.showCaptions {
                    CaptionsPanel(transcription: viewModel.transcription)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 16)
                } else {
                    Spacer()
                }

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

                    // Second row: transcribe, video, contacts
                    HStack(spacing: 60) {
                        CallControlButton(
                            icon: viewModel.transcribeIcon,
                            label: viewModel.transcribeLabel,
                            isActive: viewModel.isTranscribeButtonActive,
                            action: { viewModel.toggleTranscription() }
                        )
                        .disabled(!viewModel.canTranscribe)
                        .opacity(viewModel.canTranscribe ? 1 : 0.4)

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
                .padding(.bottom, viewModel.showCaptions ? 24 : 40)

                // End call button
                Button(action: {
                    viewModel.endCall()
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
                .padding(.bottom, viewModel.showCaptions ? 30 : 50)
            }

            // Consent prompt when the other person asks to transcribe
            if viewModel.transcription.state == .peerRequested {
                VStack {
                    TranscriptionConsentBanner(
                        name: viewModel.displayName,
                        onAllow: { viewModel.transcription.accept() },
                        onDecline: { viewModel.transcription.decline() }
                    )
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    Spacer()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
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
        .animation(.easeInOut(duration: 0.25), value: viewModel.showCaptions)
        .animation(.easeInOut(duration: 0.25), value: viewModel.transcription.state)
    }
}

// MARK: - Transcription UI

/// "● Transcribing" / "Waiting for approval…" / notices, under the call status.
struct TranscriptionStatusView: View {
    @ObservedObject var transcription: CallTranscription

    var body: some View {
        VStack(spacing: 4) {
            switch transcription.state {
            case .active:
                HStack(spacing: 6) {
                    Circle().fill(Color.red).frame(width: 8, height: 8)
                    Text(transcription.usingDemoAudio ? "Transcribing · demo audio" : "Transcribing")
                }
                .font(.system(size: 13, weight: .semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color.red.opacity(0.15)))
                .foregroundColor(.red)
                .accessibilityElement(children: .combine)
            case .waitingForPeer:
                Label("Waiting for the other person to allow transcription…", systemImage: "hourglass")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            default:
                EmptyView()
            }

            if let notice = transcription.notice {
                Text(notice)
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
        }
    }
}

/// Asks this user to allow the other person's transcription request.
struct TranscriptionConsentBanner: View {
    let name: String
    let onAllow: () -> Void
    let onDecline: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Transcription request", systemImage: "captions.bubble.fill")
                .font(.headline)
            Text("\(name) wants to transcribe this call. Each phone transcribes its own side, you both see live captions, and a summary is saved to Recents. You can stop it at any time.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 12) {
                Button(role: .cancel, action: onDecline) {
                    Text("Decline").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                Button(action: onAllow) {
                    Text("Allow").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16).fill(.regularMaterial))
        .shadow(color: .black.opacity(0.2), radius: 12, y: 4)
    }
}

/// Live captions from both sides, newest at the bottom.
struct CaptionsPanel: View {
    @ObservedObject var transcription: CallTranscription

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if transcription.lines.isEmpty {
                        Text(transcription.isActive ? "Listening…" : "No captions yet")
                            .font(.system(size: 15))
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, 20)
                    }
                    ForEach(transcription.lines) { line in
                        CaptionRow(line: line)
                            .id(rowId(line))
                    }
                }
                .padding(12)
            }
            .onChange(of: transcription.lines.last?.text) {
                guard let last = transcription.lines.last else { return }
                withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(rowId(last), anchor: .bottom) }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.primary.opacity(0.06)))
        .accessibilityLabel("Live captions")
    }

    private func rowId(_ line: TranscriptLine) -> String { "\(line.speaker.rawValue)-\(line.id)" }
}

struct CaptionRow: View {
    let line: TranscriptLine

    var body: some View {
        VStack(alignment: line.speaker == .me ? .trailing : .leading, spacing: 2) {
            Text(line.speaker == .me ? "You" : "Them")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
                .textCase(.uppercase)
            Text(line.text)
                .font(.system(size: 16))
                .foregroundColor(line.isFinal ? .primary : .secondary)
                .multilineTextAlignment(line.speaker == .me ? .trailing : .leading)
        }
        .frame(maxWidth: .infinity, alignment: line.speaker == .me ? .trailing : .leading)
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
    @Published var showKeypad = false
    @Published var dtmfDigits = ""
    @Published var callDuration: TimeInterval = 0

    private let call: Call
    private let callManager = CallManager.shared
    private var timer: Timer?
    private var cancellables = Set<AnyCancellable>()

    var transcription: CallTranscription { call.transcription }

    /// Captions take the place of the avatar once transcription has started.
    var showCaptions: Bool { transcription.isActive || !transcription.lines.isEmpty }

    var canTranscribe: Bool {
        call.state == .connected && transcription.state != .peerRequested
    }

    var transcribeIcon: String {
        transcription.isActive ? "captions.bubble.fill" : "captions.bubble"
    }

    var transcribeLabel: String {
        switch transcription.state {
        case .active: return "stop"
        case .waitingForPeer: return "cancel"
        default: return "transcribe"
        }
    }

    var isTranscribeButtonActive: Bool {
        transcription.state == .active || transcription.state == .waitingForPeer
    }

    var isMuted: Bool { call.isMuted }
    var isSpeakerOn: Bool { call.isSpeakerOn }
    var isVideoEnabled: Bool { call.isVideoEnabled }

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
        if call.state == .connected {
            return formatDuration(callDuration)
        }
        if let detail = call.statusDetail, !detail.isEmpty {
            return "\(call.state.description) · \(detail)"
        }
        return call.state.description
    }

    init(call: Call) {
        self.call = call

        // Re-render whenever the Call changes (state, mute, speaker...).
        call.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        call.transcription.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        // Start the duration timer when the call connects.
        call.$state
            .removeDuplicates()
            .sink { [weak self] state in
                guard let self else { return }
                if state == .connected {
                    self.startTimer()
                } else if state == .ended || state == .failed {
                    self.timer?.invalidate()
                }
            }
            .store(in: &cancellables)
    }

    deinit {
        timer?.invalidate()
    }

    private func startTimer() {
        timer?.invalidate()
        callDuration = call.duration
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.callDuration = self.call.duration
            }
        }
    }

    func toggleMute() {
        callManager.toggleMute()
    }

    func toggleSpeaker() {
        callManager.toggleSpeaker()
    }

    func toggleVideo() {
        callManager.toggleVideo()
    }

    func toggleKeypad() {
        withAnimation {
            showKeypad.toggle()
        }
    }

    func toggleTranscription() {
        switch transcription.state {
        case .active, .waitingForPeer:
            transcription.stop()
        case .off, .declined:
            transcription.request()
        case .peerRequested:
            break
        }
    }

    func showContacts() {
        // TODO: Implement show contacts
        print("Show contacts tapped")
    }

    func sendDTMF(_ digit: String) {
        dtmfDigits += digit
        callManager.sendDTMF(digit)
    }

    func endCall() {
        timer?.invalidate()
        callManager.endCall()
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

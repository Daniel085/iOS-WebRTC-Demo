//
//  KeypadView.swift
//  WebRTCDialer
//
//  Created by Claude Code
//

import SwiftUI
import Combine

struct KeypadView: View {
    @StateObject private var viewModel = KeypadViewModel()
    @StateObject private var callManager = CallManager.shared
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        NavigationView {
            GeometryReader { geometry in
                VStack(spacing: 0) {
                    // Phone number display with more space at top
                    VStack(spacing: 8) {
                        Text(viewModel.phoneNumber.isEmpty ? "" : viewModel.phoneNumber)
                            .font(.system(size: 36, weight: .light))
                            .foregroundColor(.primary)
                            .frame(height: 50)
                            .minimumScaleFactor(0.5)
                            .lineLimit(1)

                        // Add Name placeholder if phone number exists
                        if !viewModel.phoneNumber.isEmpty {
                            Text("Add Number")
                                .font(.system(size: 17))
                                .foregroundColor(.blue)
                        }
                    }
                    .frame(height: 120)
                    .padding(.top, 20)

                    Spacer()

                    // Keypad grid - native iOS style
                    VStack(spacing: 16) {
                        ForEach(0..<4) { row in
                            HStack(spacing: geometry.size.width > 400 ? 50 : 35) {
                                ForEach(0..<3) { col in
                                    if row == 3 {
                                        // Last row: *, 0, #
                                        if col == 0 {
                                            KeypadButton(title: "*", subtitle: "", isLargeScreen: geometry.size.width > 400) {
                                                viewModel.addDigit("*")
                                            }
                                        } else if col == 1 {
                                            KeypadButton(title: "0", subtitle: "+", isLargeScreen: geometry.size.width > 400) {
                                                viewModel.addDigit("0")
                                            }
                                        } else {
                                            KeypadButton(title: "#", subtitle: "", isLargeScreen: geometry.size.width > 400) {
                                                viewModel.addDigit("#")
                                            }
                                        }
                                    } else {
                                        // Digits 1-9
                                        let index = row * 3 + col
                                        if index < 9 {
                                            KeypadButton(
                                                title: "\(index + 1)",
                                                subtitle: viewModel.getLetters(for: index + 1),
                                                isLargeScreen: geometry.size.width > 400
                                            ) {
                                                viewModel.addDigit("\(index + 1)")
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 40)

                    Spacer()

                    // Bottom action area
                    HStack(spacing: 80) {
                        // Left spacer for symmetry
                        Color.clear
                            .frame(width: 65, height: 65)

                        // Call button (centered)
                        Button(action: {
                            viewModel.makeCall(isVideo: false)
                        }) {
                            Image(systemName: "phone.fill")
                                .font(.system(size: 28, weight: .medium))
                                .foregroundColor(.white)
                                .frame(width: 65, height: 65)
                                .background(
                                    Circle()
                                        .fill(viewModel.phoneNumber.isEmpty ? Color.green.opacity(0.3) : Color.green)
                                )
                        }
                        .disabled(viewModel.phoneNumber.isEmpty)

                        // Delete button (right)
                        Button(action: {
                            viewModel.deleteDigit()
                        }) {
                            Image(systemName: "delete.left.fill")
                                .font(.system(size: 24))
                                .foregroundColor(viewModel.phoneNumber.isEmpty ? .clear : .primary)
                                .frame(width: 65, height: 65)
                        }
                        .disabled(viewModel.phoneNumber.isEmpty)
                    }
                    .padding(.bottom, 40)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Keypad")
                        .font(.headline)
                }
            }
            .fullScreenCover(item: $callManager.activeCall) { call in
                ActiveCallView(call: call)
            }
            .fullScreenCover(item: $callManager.incomingCall) { call in
                IncomingCallView(call: call)
            }
        }
    }
}

struct KeypadButton: View {
    let title: String
    let subtitle: String
    let isLargeScreen: Bool
    let action: () -> Void

    @Environment(\.colorScheme) var colorScheme

    private var buttonSize: CGFloat {
        isLargeScreen ? 80 : 75
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: -2) {
                Text(title)
                    .font(.system(size: 36, weight: .light))
                    .foregroundColor(.primary)

                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.primary)
                        .opacity(0.5)
                        .tracking(1.5)
                }
            }
            .frame(width: buttonSize, height: buttonSize)
            .background(
                Circle()
                    .fill(colorScheme == .dark ? Color(white: 0.2) : Color(white: 0.95))
            )
            .contentShape(Circle())
        }
        .buttonStyle(KeypadButtonStyle())
    }
}

struct KeypadButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.5 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

@MainActor
class KeypadViewModel: ObservableObject {
    @Published var phoneNumber = ""
    @Published var showActiveCall = false

    private let callManager = CallManager.shared

    func addDigit(_ digit: String) {
        phoneNumber += digit
    }

    func deleteDigit() {
        if !phoneNumber.isEmpty {
            phoneNumber.removeLast()
        }
    }

    func makeCall(isVideo: Bool) {
        guard !phoneNumber.isEmpty else { return }
        callManager.startCall(to: phoneNumber, isVideo: isVideo)
        showActiveCall = true
    }

    func getLetters(for digit: Int) -> String {
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

#Preview {
    KeypadView()
}

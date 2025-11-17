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

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Spacer()

                // Phone number display
                Text(viewModel.phoneNumber.isEmpty ? "Enter phone number" : viewModel.phoneNumber)
                    .font(.largeTitle)
                    .foregroundColor(viewModel.phoneNumber.isEmpty ? .gray : .primary)
                    .padding()

                Spacer()

                // Keypad grid
                VStack(spacing: 15) {
                    ForEach(0..<4) { row in
                        HStack(spacing: 30) {
                            ForEach(0..<3) { col in
                                let index = row * 3 + col
                                if row == 3 {
                                    // Last row: *, 0, #
                                    if col == 0 {
                                        KeypadButton(title: "*", subtitle: "") {
                                            viewModel.addDigit("*")
                                        }
                                    } else if col == 1 {
                                        KeypadButton(title: "0", subtitle: "+") {
                                            viewModel.addDigit("0")
                                        }
                                    } else {
                                        KeypadButton(title: "#", subtitle: "") {
                                            viewModel.addDigit("#")
                                        }
                                    }
                                } else if index < 9 {
                                    // Digits 1-9
                                    KeypadButton(
                                        title: "\(index + 1)",
                                        subtitle: viewModel.getLetters(for: index + 1)
                                    ) {
                                        viewModel.addDigit("\(index + 1)")
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal)

                Spacer()

                // Call buttons
                HStack(spacing: 40) {
                    // Video call button
                    Button(action: {
                        viewModel.makeCall(isVideo: true)
                    }) {
                        Image(systemName: "video.fill")
                            .font(.title2)
                            .foregroundColor(.white)
                            .frame(width: 60, height: 60)
                            .background(Color.blue)
                            .clipShape(Circle())
                    }
                    .disabled(viewModel.phoneNumber.isEmpty)
                    .opacity(viewModel.phoneNumber.isEmpty ? 0.5 : 1)

                    // Voice call button
                    Button(action: {
                        viewModel.makeCall(isVideo: false)
                    }) {
                        Image(systemName: "phone.fill")
                            .font(.title2)
                            .foregroundColor(.white)
                            .frame(width: 70, height: 70)
                            .background(Color.green)
                            .clipShape(Circle())
                    }
                    .disabled(viewModel.phoneNumber.isEmpty)
                    .opacity(viewModel.phoneNumber.isEmpty ? 0.5 : 1)

                    // Delete button
                    Button(action: {
                        viewModel.deleteDigit()
                    }) {
                        Image(systemName: "delete.left")
                            .font(.title2)
                            .foregroundColor(viewModel.phoneNumber.isEmpty ? .gray : .primary)
                            .frame(width: 60, height: 60)
                    }
                    .disabled(viewModel.phoneNumber.isEmpty)
                }
                .padding(.bottom, 30)
            }
            .navigationTitle("Keypad")
        }
    }
}

struct KeypadButton: View {
    let title: String
    let subtitle: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Text(title)
                    .font(.title)
                    .fontWeight(.semibold)

                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            }
            .frame(width: 75, height: 75)
            .background(Color.gray.opacity(0.1))
            .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

@MainActor
class KeypadViewModel: ObservableObject {
    @Published var phoneNumber = ""

    func addDigit(_ digit: String) {
        phoneNumber += digit
    }

    func deleteDigit() {
        if !phoneNumber.isEmpty {
            phoneNumber.removeLast()
        }
    }

    func makeCall(isVideo: Bool) {
        // TODO: Implement call functionality
        print("Making \(isVideo ? "video" : "audio") call to: \(phoneNumber)")
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

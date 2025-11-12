//
//  KeypadView.swift
//  WebRTCDialer
//
//  Keypad dial screen
//

import SwiftUI

struct KeypadView: View {
    @State private var phoneNumber = ""

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            // Phone number display
            Text(phoneNumber.isEmpty ? " " : phoneNumber)
                .font(.system(size: 32, weight: .light))
                .frame(height: 50)

            Spacer()

            // Keypad
            VStack(spacing: 15) {
                HStack(spacing: 20) {
                    KeypadButton(digit: "1", letters: "") { phoneNumber.append("1") }
                    KeypadButton(digit: "2", letters: "ABC") { phoneNumber.append("2") }
                    KeypadButton(digit: "3", letters: "DEF") { phoneNumber.append("3") }
                }

                HStack(spacing: 20) {
                    KeypadButton(digit: "4", letters: "GHI") { phoneNumber.append("4") }
                    KeypadButton(digit: "5", letters: "JKL") { phoneNumber.append("5") }
                    KeypadButton(digit: "6", letters: "MNO") { phoneNumber.append("6") }
                }

                HStack(spacing: 20) {
                    KeypadButton(digit: "7", letters: "PQRS") { phoneNumber.append("7") }
                    KeypadButton(digit: "8", letters: "TUV") { phoneNumber.append("8") }
                    KeypadButton(digit: "9", letters: "WXYZ") { phoneNumber.append("9") }
                }

                HStack(spacing: 20) {
                    KeypadButton(digit: "*", letters: "") { phoneNumber.append("*") }
                    KeypadButton(digit: "0", letters: "+") { phoneNumber.append("0") }
                    KeypadButton(digit: "#", letters: "") { phoneNumber.append("#") }
                }
            }
            .padding(.horizontal, 40)

            Spacer()

            // Action buttons
            HStack(spacing: 60) {
                // Video call button
                Button(action: {
                    // TODO: Initiate video call
                }) {
                    Image(systemName: "video.fill")
                        .font(.system(size: 28))
                        .foregroundColor(phoneNumber.isEmpty ? .gray : .blue)
                }
                .disabled(phoneNumber.isEmpty)

                // Voice call button
                Button(action: {
                    // TODO: Initiate voice call
                }) {
                    Image(systemName: "phone.fill")
                        .font(.system(size: 28))
                        .foregroundColor(.white)
                        .frame(width: 60, height: 60)
                        .background(phoneNumber.isEmpty ? Color.gray : Color.green)
                        .clipShape(Circle())
                }
                .disabled(phoneNumber.isEmpty)

                // Backspace button
                Button(action: {
                    if !phoneNumber.isEmpty {
                        phoneNumber.removeLast()
                    }
                }) {
                    Image(systemName: "delete.left")
                        .font(.system(size: 28))
                        .foregroundColor(phoneNumber.isEmpty ? .gray : .primary)
                }
                .disabled(phoneNumber.isEmpty)
            }
            .padding(.bottom, 40)
        }
    }
}

struct KeypadButton: View {
    let digit: String
    let letters: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Text(digit)
                    .font(.system(size: 32, weight: .light))

                if !letters.isEmpty {
                    Text(letters)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .frame(width: 75, height: 75)
            .background(Color.gray.opacity(0.1))
            .clipShape(Circle())
        }
        .foregroundColor(.primary)
    }
}

struct KeypadView_Previews: PreviewProvider {
    static var previews: some View {
        KeypadView()
    }
}

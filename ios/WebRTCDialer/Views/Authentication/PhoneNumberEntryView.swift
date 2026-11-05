//
//  PhoneNumberEntryView.swift
//  WebRTCDialer
//
//  Created by Claude Code
//

import SwiftUI
import Combine

struct PhoneNumberEntryView: View {
    @Binding var phoneNumber: String
    @Binding var isVerifying: Bool
    @Binding var devCode: String?
    @StateObject private var viewModel = PhoneNumberEntryViewModel()
    @State private var input = ""
    @FocusState private var isFieldFocused: Bool

    private var e164Number: String? {
        PhoneNumberHelper.e164(from: input)
    }

    var body: some View {
        VStack(spacing: 30) {
            Spacer()

            // Logo or App Name
            VStack(spacing: 10) {
                Image(systemName: "phone.circle.fill")
                    .resizable()
                    .frame(width: 80, height: 80)
                    .foregroundColor(.blue)

                Text("WebRTC Dialer")
                    .font(.largeTitle)
                    .fontWeight(.bold)
            }

            Spacer()

            // Phone Number Entry
            VStack(spacing: 16) {
                Text("Enter your phone number")
                    .font(.title2)
                    .fontWeight(.semibold)

                HStack(spacing: 12) {
                    Text(PhoneNumberHelper.countryCodePrefix)
                        .font(.title3)
                        .foregroundColor(.secondary)

                    Divider()
                        .frame(height: 24)

                    TextField("(408) 555-0123", text: $input)
                        .keyboardType(.phonePad)
                        .textContentType(.telephoneNumber)
                        .font(.title3)
                        .focused($isFieldFocused)
                        .disabled(viewModel.isLoading)

                    if e164Number != nil {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .transition(.opacity)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(viewModel.errorMessage == nil ? Color(.systemGray4) : Color.red, lineWidth: 1)
                )
                .animation(.easeInOut(duration: 0.15), value: e164Number != nil)

                if let errorMessage = viewModel.errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.circle.fill")
                        .font(.footnote)
                        .foregroundColor(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text("Enter your mobile number, including area code")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Button(action: {
                    guard let number = e164Number else { return }
                    isFieldFocused = false
                    Task {
                        await viewModel.sendVerificationCode(phoneNumber: number)
                        if viewModel.codeSent {
                            phoneNumber = number
                            devCode = viewModel.devCode
                            isVerifying = true
                        }
                    }
                }) {
                    if viewModel.isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .frame(maxWidth: .infinity)
                            .padding()
                    } else {
                        Text("Continue")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .padding()
                    }
                }
                .background(e164Number == nil ? Color.gray : Color.blue)
                .foregroundColor(.white)
                .cornerRadius(10)
                .disabled(e164Number == nil || viewModel.isLoading)
            }
            .padding(.horizontal, 40)

            Spacer()

            Text("We'll send you a verification code")
                .font(.caption)
                .foregroundColor(.gray)
                .padding(.bottom, 30)
        }
        .contentShape(Rectangle())
        .onTapGesture { isFieldFocused = false }
        .onAppear {
            if input.isEmpty && !phoneNumber.isEmpty {
                input = PhoneNumberHelper.displayString(fromE164: phoneNumber)
            }
        }
        .onChange(of: input) { _, newValue in
            let formatted = PhoneNumberHelper.formatAsYouType(newValue)
            if formatted != newValue {
                input = formatted
            }
            viewModel.errorMessage = nil
        }
        .onChange(of: isFieldFocused) { _, focused in
            if !focused && !input.isEmpty && e164Number == nil {
                viewModel.errorMessage = PhoneNumberEntryViewModel.incompleteNumberMessage(for: input)
            }
        }
    }
}

@MainActor
class PhoneNumberEntryViewModel: ObservableObject {
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var codeSent = false
    @Published var devCode: String?

    func sendVerificationCode(phoneNumber: String) async {
        isLoading = true
        errorMessage = nil
        codeSent = false
        devCode = nil

        do {
            devCode = try await AuthenticationService.shared.sendVerificationCode(phoneNumber: phoneNumber)
            codeSent = true
        } catch {
            errorMessage = Self.friendlyMessage(for: error)
        }

        isLoading = false
    }

    static func incompleteNumberMessage(for input: String) -> String {
        if PhoneNumberHelper.digitCount(input) < 10 {
            return "That number looks too short. Enter all 10 digits, including the area code."
        }
        return "That doesn't look like a valid phone number. Check the area code and try again."
    }

    static func friendlyMessage(for error: Error) -> String {
        if error is URLError {
            return "Can't reach the server. Check your connection and try again."
        }
        if case AuthError.serverError(let message) = error {
            if message.contains("phoneNumber") || message.contains("pattern") {
                return "That doesn't look like a valid phone number. Check the area code and try again."
            }
            if message.count <= 80 {
                return message
            }
        }
        return "Something went wrong sending your code. Please try again."
    }
}

#Preview {
    PhoneNumberEntryView(phoneNumber: .constant(""), isVerifying: .constant(false), devCode: .constant(nil))
}

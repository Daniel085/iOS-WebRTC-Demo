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
            VStack(spacing: 20) {
                Text("Enter your phone number")
                    .font(.title2)
                    .fontWeight(.semibold)

                TextField("Phone Number", text: $phoneNumber)
                    .keyboardType(.phonePad)
                    .textFieldStyle(.roundedBorder)
                    .font(.title3)
                    .multilineTextAlignment(.center)
                    .disabled(viewModel.isLoading)

                Text("Example: +11234567890")
                    .font(.caption)
                    .foregroundColor(.gray)

                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .foregroundColor(.red)
                        .font(.caption)
                }

                Button(action: {
                    Task {
                        await viewModel.sendVerificationCode(phoneNumber: phoneNumber)
                        if viewModel.codeSent {
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
                .background(phoneNumber.isEmpty ? Color.gray : Color.blue)
                .foregroundColor(.white)
                .cornerRadius(10)
                .disabled(phoneNumber.isEmpty || viewModel.isLoading)
            }
            .padding(.horizontal, 40)

            Spacer()

            Text("We'll send you a verification code")
                .font(.caption)
                .foregroundColor(.gray)
                .padding(.bottom, 30)
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
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }
}

#Preview {
    PhoneNumberEntryView(phoneNumber: .constant(""), isVerifying: .constant(false), devCode: .constant(nil))
}

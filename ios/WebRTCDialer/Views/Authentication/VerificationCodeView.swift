//
//  VerificationCodeView.swift
//  WebRTCDialer
//
//  Created by Claude Code
//

import SwiftUI
import Combine

struct VerificationCodeView: View {
    let phoneNumber: String
    let devCode: String?
    @Binding var isVerifying: Bool
    @EnvironmentObject var appState: AppState
    @StateObject private var viewModel = VerificationCodeViewModel()
    @State private var code = ""

    var body: some View {
        VStack(spacing: 30) {
            Spacer()

            // Header
            VStack(spacing: 10) {
                Image(systemName: "envelope.circle.fill")
                    .resizable()
                    .frame(width: 80, height: 80)
                    .foregroundColor(.blue)

                Text("Enter Verification Code")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("Sent to \(phoneNumber)")
                    .font(.subheadline)
                    .foregroundColor(.gray)
            }

            Spacer()

            // Code Entry
            VStack(spacing: 20) {
                TextField("000000", text: $code)
                    .keyboardType(.numberPad)
                    .textFieldStyle(.roundedBorder)
                    .font(.title)
                    .multilineTextAlignment(.center)
                    .disabled(viewModel.isLoading)

                if let devCode = devCode {
                    VStack(spacing: 8) {
                        Text("Development Mode")
                            .font(.caption)
                            .foregroundColor(.orange)
                        Text("Code: \(devCode)")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.orange)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(Color.orange.opacity(0.1))
                            .cornerRadius(8)
                    }
                }

                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .foregroundColor(.red)
                        .font(.caption)
                }

                Button(action: {
                    Task {
                        await viewModel.verifyCode(phoneNumber: phoneNumber, code: code)
                        if viewModel.isAuthenticated {
                            appState.login()
                        }
                    }
                }) {
                    if viewModel.isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .frame(maxWidth: .infinity)
                            .padding()
                    } else {
                        Text("Verify")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .padding()
                    }
                }
                .background(code.count != 6 ? Color.gray : Color.blue)
                .foregroundColor(.white)
                .cornerRadius(10)
                .disabled(code.count != 6 || viewModel.isLoading)
            }
            .padding(.horizontal, 40)

            Spacer()

            Button(action: {
                isVerifying = false
            }) {
                Text("Change Phone Number")
                    .foregroundColor(.blue)
            }
            .padding(.bottom, 30)
        }
    }
}

@MainActor
class VerificationCodeViewModel: ObservableObject {
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var isAuthenticated = false

    func verifyCode(phoneNumber: String, code: String) async {
        isLoading = true
        errorMessage = nil
        isAuthenticated = false

        do {
            _ = try await AuthenticationService.shared.verifyCode(phoneNumber: phoneNumber, code: code)
            isAuthenticated = true
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }
}

#Preview {
    VerificationCodeView(phoneNumber: "+1234567890", devCode: "123456", isVerifying: .constant(true))
        .environmentObject(AppState())
}

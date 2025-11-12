//
//  VerificationCodeView.swift
//  WebRTCDialer
//
//  Verification code entry screen
//

import SwiftUI

struct VerificationCodeView: View {
    @StateObject private var viewModel = VerificationViewModel()
    @EnvironmentObject var appState: AppState
    @Binding var showVerification: Bool

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "envelope.circle.fill")
                .font(.system(size: 80))
                .foregroundColor(.green)

            Text("Enter Verification Code")
                .font(.title2)
                .bold()

            if let phoneNumber = AuthenticationService.shared.phoneNumber {
                Text("Sent to \(phoneNumber)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            // Code input field (visible but styled as 6 boxes)
            HStack(spacing: 10) {
                ForEach(0..<6, id: \.self) { index in
                    CodeDigitView(digit: viewModel.getDigit(at: index))
                }
            }
            .padding(.horizontal, 40)

            TextField("", text: $viewModel.code)
                .keyboardType(.numberPad)
                .opacity(0.01) // Nearly invisible but still functional
                .frame(height: 1)
                .padding(.horizontal, 40)

            if let error = viewModel.errorMessage {
                Text(error)
                    .foregroundColor(.red)
                    .font(.caption)
            }

            Button(action: {
                Task {
                    await viewModel.verifyCode()
                    if viewModel.isVerified {
                        appState.login()
                    }
                }
            }) {
                if viewModel.isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                } else {
                    Text("Verify")
                        .fontWeight(.semibold)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(viewModel.code.count == 6 ? Color.blue : Color.gray)
            .foregroundColor(.white)
            .cornerRadius(10)
            .padding(.horizontal, 40)
            .disabled(viewModel.code.count != 6 || viewModel.isLoading)

            Button("Resend Code") {
                Task {
                    await viewModel.resendCode()
                }
            }
            .foregroundColor(.blue)

            Spacer()
        }
        .padding()
    }
}

struct CodeDigitView: View {
    let digit: String?

    var body: some View {
        Text(digit ?? "")
            .font(.title)
            .frame(width: 45, height: 55)
            .background(Color.gray.opacity(0.1))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(digit != nil ? Color.blue : Color.gray.opacity(0.3), lineWidth: 2)
            )
    }
}

@MainActor
class VerificationViewModel: ObservableObject {
    @Published var code = "" {
        didSet {
            // Limit to 6 digits
            if code.count > 6 {
                code = String(code.prefix(6))
            }
        }
    }
    @Published var errorMessage: String?
    @Published var isLoading = false
    @Published var isVerified = false

    func getDigit(at index: Int) -> String? {
        guard index < code.count else { return nil }
        let digitIndex = code.index(code.startIndex, offsetBy: index)
        return String(code[digitIndex])
    }

    func verifyCode() async {
        errorMessage = nil
        isLoading = true

        do {
            _ = try await AuthenticationService.shared.verifyCode(code)
            isVerified = true
            isLoading = false
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }

    func resendCode() async {
        guard let phoneNumber = AuthenticationService.shared.phoneNumber else { return }

        do {
            try await AuthenticationService.shared.sendVerificationCode(phoneNumber: phoneNumber)
            code = ""
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct VerificationCodeView_Previews: PreviewProvider {
    static var previews: some View {
        VerificationCodeView(showVerification: .constant(true))
            .environmentObject(AppState())
    }
}

//
//  PhoneNumberEntryView.swift
//  WebRTCDialer
//
//  Phone number entry screen
//

import SwiftUI

struct PhoneNumberEntryView: View {
    @StateObject private var viewModel = PhoneNumberViewModel()
    @Binding var showVerification: Bool

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "phone.circle.fill")
                .font(.system(size: 80))
                .foregroundColor(.blue)

            Text("Enter Your Phone Number")
                .font(.title2)
                .bold()

            Text("We'll send you a verification code")
                .font(.subheadline)
                .foregroundColor(.secondary)

            TextField("Phone Number", text: $viewModel.phoneNumber)
                .keyboardType(.phonePad)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding(.horizontal, 40)
                .font(.title3)
                .autocapitalization(.none)

            if let error = viewModel.errorMessage {
                Text(error)
                    .foregroundColor(.red)
                    .font(.caption)
                    .padding(.horizontal, 40)
            }

            Button(action: {
                Task {
                    await viewModel.sendVerificationCode()
                    if viewModel.codeSent {
                        showVerification = true
                    }
                }
            }) {
                if viewModel.isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                } else {
                    Text("Send Code")
                        .fontWeight(.semibold)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(viewModel.isValidPhoneNumber ? Color.blue : Color.gray)
            .foregroundColor(.white)
            .cornerRadius(10)
            .padding(.horizontal, 40)
            .disabled(!viewModel.isValidPhoneNumber || viewModel.isLoading)

            Spacer()
        }
        .padding()
    }
}

@MainActor
class PhoneNumberViewModel: ObservableObject {
    @Published var phoneNumber = ""
    @Published var errorMessage: String?
    @Published var isLoading = false
    @Published var codeSent = false

    var isValidPhoneNumber: Bool {
        let cleaned = phoneNumber.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
        return cleaned.count >= 10
    }

    func sendVerificationCode() async {
        errorMessage = nil
        isLoading = true

        do {
            try await AuthenticationService.shared.sendVerificationCode(phoneNumber: phoneNumber)
            codeSent = true
            isLoading = false
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }
}

struct PhoneNumberEntryView_Previews: PreviewProvider {
    static var previews: some View {
        PhoneNumberEntryView(showVerification: .constant(false))
    }
}

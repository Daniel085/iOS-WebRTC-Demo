//
//  AuthenticationView.swift
//  WebRTCDialer
//
//  Created by Claude Code
//

import SwiftUI
import Combine

struct AuthenticationView: View {
    @EnvironmentObject var appState: AppState
    @State private var phoneNumber = ""
    @State private var isVerifying = false
    @State private var devCode: String?

    var body: some View {
        NavigationView {
            if isVerifying {
                VerificationCodeView(phoneNumber: phoneNumber, devCode: devCode, isVerifying: $isVerifying)
            } else {
                PhoneNumberEntryView(phoneNumber: $phoneNumber, isVerifying: $isVerifying, devCode: $devCode)
            }
        }
    }
}

#Preview {
    AuthenticationView()
        .environmentObject(AppState())
}

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

    var body: some View {
        NavigationView {
            if isVerifying {
                VerificationCodeView(phoneNumber: phoneNumber, isVerifying: $isVerifying)
            } else {
                PhoneNumberEntryView(phoneNumber: $phoneNumber, isVerifying: $isVerifying)
            }
        }
    }
}

#Preview {
    AuthenticationView()
        .environmentObject(AppState())
}

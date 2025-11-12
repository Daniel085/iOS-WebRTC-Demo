//
//  AuthenticationView.swift
//  WebRTCDialer
//
//  Main authentication flow coordinator
//

import SwiftUI

struct AuthenticationView: View {
    @State private var showVerification = false

    var body: some View {
        if showVerification {
            VerificationCodeView(showVerification: $showVerification)
        } else {
            PhoneNumberEntryView(showVerification: $showVerification)
        }
    }
}

struct AuthenticationView_Previews: PreviewProvider {
    static var previews: some View {
        AuthenticationView()
    }
}

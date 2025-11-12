//
//  ContactsView.swift
//  WebRTCDialer
//
//  Contacts list screen
//

import SwiftUI

struct ContactsView: View {
    var body: some View {
        NavigationView {
            VStack {
                Text("No Contacts")
                    .font(.title2)
                    .foregroundColor(.secondary)
                    .padding()

                Image(systemName: "person.2.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.secondary)

                Text("Grant access to your contacts to see who you can call")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding()

                Button("Allow Access") {
                    // Will implement contacts permission request
                }
                .buttonStyle(.borderedProminent)
            }
            .navigationTitle("Contacts")
        }
    }
}

struct ContactsView_Previews: PreviewProvider {
    static var previews: some View {
        ContactsView()
    }
}

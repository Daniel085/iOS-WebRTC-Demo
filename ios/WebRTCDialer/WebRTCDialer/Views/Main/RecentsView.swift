//
//  RecentsView.swift
//  WebRTCDialer
//
//  Recent calls screen
//

import SwiftUI

struct RecentsView: View {
    var body: some View {
        NavigationView {
            VStack {
                Text("No Recent Calls")
                    .font(.title2)
                    .foregroundColor(.secondary)
                    .padding()

                Image(systemName: "phone.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.secondary)

                Text("Your call history will appear here")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding()
            }
            .navigationTitle("Recents")
        }
    }
}

struct RecentsView_Previews: PreviewProvider {
    static var previews: some View {
        RecentsView()
    }
}

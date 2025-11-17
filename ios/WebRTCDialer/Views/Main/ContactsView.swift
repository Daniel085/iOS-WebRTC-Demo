//
//  ContactsView.swift
//  WebRTCDialer
//
//  Created by Claude Code
//

import SwiftUI

struct ContactsView: View {
    @State private var contacts: [Contact] = []
    @State private var searchText = ""

    var filteredContacts: [Contact] {
        if searchText.isEmpty {
            return contacts
        }
        return contacts.filter { contact in
            contact.displayName.localizedCaseInsensitiveContains(searchText) ||
            contact.phoneNumbers.contains { $0.number.contains(searchText) }
        }
    }

    var body: some View {
        NavigationView {
            if contacts.isEmpty {
                VStack(spacing: 20) {
                    Image(systemName: "person.crop.circle")
                        .resizable()
                        .frame(width: 80, height: 80)
                        .foregroundColor(.gray)

                    Text("No Contacts")
                        .font(.title2)
                        .foregroundColor(.gray)

                    Text("Grant contacts permission to see your contacts")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)

                    Button("Grant Permission") {
                        // Request contacts permission
                    }
                    .buttonStyle(.borderedProminent)
                }
                .navigationTitle("Contacts")
            } else {
                List(filteredContacts) { contact in
                    ContactRow(contact: contact)
                }
                .searchable(text: $searchText, prompt: "Search contacts")
                .navigationTitle("Contacts")
            }
        }
    }
}

struct ContactRow: View {
    let contact: Contact

    var body: some View {
        HStack {
            // Avatar
            if let image = contact.image {
                Image(uiImage: image)
                    .resizable()
                    .frame(width: 50, height: 50)
                    .clipShape(Circle())
            } else {
                ZStack {
                    Circle()
                        .fill(Color.blue.opacity(0.3))
                        .frame(width: 50, height: 50)

                    Text(contact.initials)
                        .font(.headline)
                        .foregroundColor(.blue)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(contact.displayName)
                    .font(.body)

                if let firstNumber = contact.phoneNumbers.first {
                    Text(firstNumber.formattedNumber)
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            }

            Spacer()

            // Call buttons
            HStack(spacing: 15) {
                Button(action: {
                    // Make audio call
                }) {
                    Image(systemName: "phone.fill")
                        .foregroundColor(.blue)
                }

                Button(action: {
                    // Make video call
                }) {
                    Image(systemName: "video.fill")
                        .foregroundColor(.blue)
                }
            }
        }
        .padding(.vertical, 5)
    }
}

#Preview {
    ContactsView()
}

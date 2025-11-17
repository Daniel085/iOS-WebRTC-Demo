//
//  Contact.swift
//  WebRTCDialer
//
//  Created by Claude Code
//

import Foundation
import UIKit

/// Represents a contact from the address book
struct Contact: Identifiable {
    let id: String
    let firstName: String
    let lastName: String
    let phoneNumbers: [PhoneNumber]
    let image: UIImage?

    var displayName: String {
        let name = "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? phoneNumbers.first?.number ?? "Unknown" : name
    }

    var initials: String {
        let first = firstName.first.map { String($0) } ?? ""
        let last = lastName.first.map { String($0) } ?? ""
        return (first + last).uppercased()
    }
}

/// Represents a phone number with its label
struct PhoneNumber: Identifiable {
    let id = UUID()
    let label: String
    let number: String

    var formattedNumber: String {
        // Simple formatting - will be enhanced with PhoneNumberKit
        return number
    }
}

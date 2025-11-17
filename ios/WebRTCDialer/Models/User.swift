//
//  User.swift
//  WebRTCDialer
//
//  Created by Claude Code
//

import Foundation

/// Represents the authenticated user
struct User: Codable {
    let id: String
    let phoneNumber: String
}

/// Authentication response from server
struct AuthResponse: Codable {
    let success: Bool
    let token: String
    let user: User
}

/// Token refresh response
struct RefreshResponse: Codable {
    let success: Bool
    let token: String
}

/// Error response from server
struct ErrorResponse: Codable {
    let success: Bool
    let error: String
}

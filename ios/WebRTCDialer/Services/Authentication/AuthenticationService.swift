//
//  AuthenticationService.swift
//  WebRTCDialer
//
//  Created by Claude Code
//

import Foundation

class AuthenticationService {
    static let shared = AuthenticationService()

    private init() {}

    var isAuthenticated: Bool {
        return KeychainHelper.load(key: Constants.Keychain.authToken) != nil
    }

    var authToken: String? {
        return KeychainHelper.load(key: Constants.Keychain.authToken)
    }

    /// Send verification code to phone number
    func sendVerificationCode(phoneNumber: String) async throws {
        guard let url = URL(string: "\(Constants.API.baseURL)/auth/send-code") else {
            throw AuthError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = ["phoneNumber": phoneNumber]
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthError.invalidResponse
        }

        if httpResponse.statusCode != 200 {
            if let errorResponse = try? JSONDecoder().decode(ErrorResponse.self, from: data) {
                throw AuthError.serverError(errorResponse.error)
            }
            throw AuthError.invalidResponse
        }
    }

    /// Verify code and authenticate user
    func verifyCode(phoneNumber: String, code: String) async throws -> User {
        guard let url = URL(string: "\(Constants.API.baseURL)/auth/verify-code") else {
            throw AuthError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = ["phoneNumber": phoneNumber, "code": code]
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthError.invalidResponse
        }

        if httpResponse.statusCode != 200 {
            if let errorResponse = try? JSONDecoder().decode(ErrorResponse.self, from: data) {
                throw AuthError.serverError(errorResponse.error)
            }
            throw AuthError.invalidResponse
        }

        let authResponse = try JSONDecoder().decode(AuthResponse.self, from: data)

        // Save auth token
        KeychainHelper.save(key: Constants.Keychain.authToken, data: authResponse.token)

        // Save phone number
        UserDefaults.standard.set(phoneNumber, forKey: Constants.UserDefaults.userPhoneNumber)

        return authResponse.user
    }

    /// Refresh authentication token
    func refreshToken() async throws {
        guard let token = authToken else {
            throw AuthError.notAuthenticated
        }

        guard let url = URL(string: "\(Constants.API.baseURL)/auth/refresh") else {
            throw AuthError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthError.invalidResponse
        }

        if httpResponse.statusCode != 200 {
            throw AuthError.invalidResponse
        }

        let refreshResponse = try JSONDecoder().decode(RefreshResponse.self, from: data)

        // Save new token
        KeychainHelper.save(key: Constants.Keychain.authToken, data: refreshResponse.token)
    }

    /// Logout user
    func logout() {
        KeychainHelper.delete(key: Constants.Keychain.authToken)
        UserDefaults.standard.removeObject(forKey: Constants.UserDefaults.userPhoneNumber)
    }
}

/// Authentication errors
enum AuthError: LocalizedError {
    case invalidURL
    case invalidResponse
    case serverError(String)
    case notAuthenticated

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid server URL"
        case .invalidResponse:
            return "Invalid server response"
        case .serverError(let message):
            return message
        case .notAuthenticated:
            return "Not authenticated"
        }
    }
}

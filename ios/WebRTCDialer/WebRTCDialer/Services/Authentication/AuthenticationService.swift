//
//  AuthenticationService.swift
//  WebRTCDialer
//
//  Handles phone number authentication
//

import Foundation

/// Errors that can occur during authentication
enum AuthError: LocalizedError {
    case invalidURL
    case invalidResponse
    case serverError(String)
    case noPhoneNumber
    case notAuthenticated
    case tokenExpired

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .invalidResponse:
            return "Invalid server response"
        case .serverError(let message):
            return message
        case .noPhoneNumber:
            return "No phone number provided"
        case .notAuthenticated:
            return "Not authenticated"
        case .tokenExpired:
            return "Token expired"
        }
    }
}

/// Manages user authentication
class AuthenticationService {
    static let shared = AuthenticationService()

    private let baseURL = Constants.API.baseURL
    private let tokenKey = Constants.Keychain.authToken
    private let phoneNumberKey = Constants.UserDefaults.userPhoneNumber

    private init() {}

    /// Check if user is authenticated
    var isAuthenticated: Bool {
        return authToken != nil
    }

    /// Current authentication token
    var authToken: String? {
        get {
            return KeychainHelper.load(key: tokenKey)
        }
        set {
            if let token = newValue {
                KeychainHelper.save(key: tokenKey, data: token)
            } else {
                KeychainHelper.delete(key: tokenKey)
            }
        }
    }

    /// Current user's phone number
    var phoneNumber: String? {
        get {
            return UserDefaults.standard.string(forKey: phoneNumberKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: phoneNumberKey)
        }
    }

    /// Send verification code to phone number
    func sendVerificationCode(phoneNumber: String) async throws {
        guard let url = URL(string: "\(baseURL)/auth/send-code") else {
            throw AuthError.invalidURL
        }

        let body: [String: Any] = [
            "phoneNumber": phoneNumber
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthError.invalidResponse
        }

        if httpResponse.statusCode == 200 {
            self.phoneNumber = phoneNumber
        } else {
            let error = try? JSONDecoder().decode(ErrorResponse.self, from: data)
            throw AuthError.serverError(error?.error ?? "Unknown error")
        }
    }

    /// Verify the OTP code
    func verifyCode(_ code: String) async throws -> User {
        guard let phoneNumber = phoneNumber else {
            throw AuthError.noPhoneNumber
        }

        guard let url = URL(string: "\(baseURL)/auth/verify-code") else {
            throw AuthError.invalidURL
        }

        let body: [String: Any] = [
            "phoneNumber": phoneNumber,
            "code": code
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthError.invalidResponse
        }

        if httpResponse.statusCode == 200 {
            let authResponse = try JSONDecoder().decode(AuthResponse.self, from: data)
            self.authToken = authResponse.token
            return authResponse.user
        } else {
            let error = try? JSONDecoder().decode(ErrorResponse.self, from: data)
            throw AuthError.serverError(error?.error ?? "Invalid code")
        }
    }

    /// Logout user
    func logout() {
        authToken = nil
        phoneNumber = nil
    }

    /// Refresh authentication token
    func refreshToken() async throws {
        guard let token = authToken else {
            throw AuthError.notAuthenticated
        }

        guard let url = URL(string: "\(baseURL)/auth/refresh-token") else {
            throw AuthError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthError.invalidResponse
        }

        if httpResponse.statusCode == 200 {
            let refreshResponse = try JSONDecoder().decode(RefreshResponse.self, from: data)
            self.authToken = refreshResponse.token
        } else {
            throw AuthError.tokenExpired
        }
    }
}

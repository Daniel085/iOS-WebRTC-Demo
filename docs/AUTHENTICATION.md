# Phone Number Authentication

## Overview

The app uses phone number-based authentication to identify users uniquely. This provides a familiar authentication flow similar to WhatsApp, Signal, and other messaging apps.

## Authentication Flow

```
┌─────────────┐
│  User Opens │
│     App     │
└──────┬──────┘
       │
       ▼
┌─────────────────┐
│ Enter Phone     │  ──────────────┐
│ Number Screen   │                │
└──────┬──────────┘                │
       │                           │
       │ Submit                    │ User already
       ▼                           │ authenticated?
┌─────────────────┐                │
│ Send OTP to     │                │
│ Phone via SMS   │                │
└──────┬──────────┘                │
       │                           │
       ▼                           │
┌─────────────────┐                │
│ Enter OTP Code  │                │
└──────┬──────────┘                │
       │                           │
       │ Verify                    │
       ▼                           │
┌─────────────────┐                │
│ Backend         │                │
│ Validates OTP   │                │
└──────┬──────────┘                │
       │                           │
       │ Valid                     │
       ▼                           │
┌─────────────────┐                │
│ Issue JWT Token │                │
└──────┬──────────┘                │
       │                           │
       │◄──────────────────────────┘
       ▼
┌─────────────────┐
│ Main App Screen │
└─────────────────┘
```

## Backend Implementation

### Using Twilio Verify

Twilio Verify is a managed service for phone verification:

```javascript
// auth-service.js
const twilio = require('twilio');
const jwt = require('jsonwebtoken');

const client = twilio(
    process.env.TWILIO_ACCOUNT_SID,
    process.env.TWILIO_AUTH_TOKEN
);

const verifyServiceSid = process.env.TWILIO_VERIFY_SERVICE_SID;
const JWT_SECRET = process.env.JWT_SECRET;

// Send OTP
async function sendVerificationCode(phoneNumber) {
    try {
        const verification = await client.verify.v2
            .services(verifyServiceSid)
            .verifications
            .create({
                to: phoneNumber,
                channel: 'sms'
            });

        return {
            success: true,
            status: verification.status
        };
    } catch (error) {
        console.error('Error sending verification:', error);
        return {
            success: false,
            error: error.message
        };
    }
}

// Verify OTP
async function verifyCode(phoneNumber, code) {
    try {
        const verificationCheck = await client.verify.v2
            .services(verifyServiceSid)
            .verificationChecks
            .create({
                to: phoneNumber,
                code: code
            });

        if (verificationCheck.status === 'approved') {
            // Create or get user
            const user = await findOrCreateUser(phoneNumber);

            // Generate JWT token
            const token = jwt.sign(
                {
                    userId: user.id,
                    phoneNumber: user.phoneNumber
                },
                JWT_SECRET,
                { expiresIn: '30d' }
            );

            return {
                success: true,
                token,
                user
            };
        } else {
            return {
                success: false,
                error: 'Invalid code'
            };
        }
    } catch (error) {
        console.error('Error verifying code:', error);
        return {
            success: false,
            error: error.message
        };
    }
}

// Database operations
const db = require('./database');

async function findOrCreateUser(phoneNumber) {
    let user = await db.users.findOne({ phoneNumber });

    if (!user) {
        user = await db.users.create({
            phoneNumber,
            createdAt: new Date(),
            isActive: true
        });
    }

    return user;
}

module.exports = {
    sendVerificationCode,
    verifyCode
};
```

### API Endpoints

```javascript
// routes/auth.js
const express = require('express');
const router = express.Router();
const authService = require('../services/auth-service');
const { body, validationResult } = require('express-validator');

// Request OTP
router.post('/send-code',
    body('phoneNumber').isMobilePhone(),
    async (req, res) => {
        const errors = validationResult(req);
        if (!errors.isEmpty()) {
            return res.status(400).json({ errors: errors.array() });
        }

        const { phoneNumber } = req.body;

        // Normalize phone number to E.164 format
        const normalizedNumber = normalizePhoneNumber(phoneNumber);

        const result = await authService.sendVerificationCode(normalizedNumber);

        if (result.success) {
            res.json({
                success: true,
                message: 'Verification code sent'
            });
        } else {
            res.status(400).json({
                success: false,
                error: result.error
            });
        }
    }
);

// Verify OTP
router.post('/verify-code',
    body('phoneNumber').isMobilePhone(),
    body('code').isLength({ min: 4, max: 6 }),
    async (req, res) => {
        const errors = validationResult(req);
        if (!errors.isEmpty()) {
            return res.status(400).json({ errors: errors.array() });
        }

        const { phoneNumber, code } = req.body;
        const normalizedNumber = normalizePhoneNumber(phoneNumber);

        const result = await authService.verifyCode(normalizedNumber, code);

        if (result.success) {
            res.json({
                success: true,
                token: result.token,
                user: {
                    id: result.user.id,
                    phoneNumber: result.user.phoneNumber
                }
            });
        } else {
            res.status(400).json({
                success: false,
                error: result.error
            });
        }
    }
);

// Refresh token
router.post('/refresh-token',
    authenticateToken,
    async (req, res) => {
        const { userId, phoneNumber } = req.user;

        const newToken = jwt.sign(
            { userId, phoneNumber },
            process.env.JWT_SECRET,
            { expiresIn: '30d' }
        );

        res.json({
            success: true,
            token: newToken
        });
    }
);

function normalizePhoneNumber(phoneNumber) {
    // Remove all non-numeric characters
    let digits = phoneNumber.replace(/\D/g, '');

    // Add country code if missing (assuming US)
    if (digits.length === 10) {
        digits = '1' + digits;
    }

    return '+' + digits;
}

function authenticateToken(req, res, next) {
    const authHeader = req.headers['authorization'];
    const token = authHeader && authHeader.split(' ')[1];

    if (!token) {
        return res.status(401).json({ error: 'No token provided' });
    }

    jwt.verify(token, process.env.JWT_SECRET, (err, user) => {
        if (err) {
            return res.status(403).json({ error: 'Invalid token' });
        }
        req.user = user;
        next();
    });
}

module.exports = router;
```

## iOS Implementation

### Authentication Service

```swift
import Foundation

class AuthenticationService {
    static let shared = AuthenticationService()

    private let baseURL = "https://your-api.com"
    private let tokenKey = "authToken"
    private let phoneNumberKey = "userPhoneNumber"

    var isAuthenticated: Bool {
        return authToken != nil
    }

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

    var phoneNumber: String? {
        get {
            return UserDefaults.standard.string(forKey: phoneNumberKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: phoneNumberKey)
        }
    }

    // MARK: - Send Verification Code

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

    // MARK: - Verify Code

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

    // MARK: - Logout

    func logout() {
        authToken = nil
        phoneNumber = nil
    }

    // MARK: - Token Refresh

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

// MARK: - Models

struct User: Codable {
    let id: String
    let phoneNumber: String
}

struct AuthResponse: Codable {
    let success: Bool
    let token: String
    let user: User
}

struct RefreshResponse: Codable {
    let success: Bool
    let token: String
}

struct ErrorResponse: Codable {
    let success: Bool
    let error: String
}

// MARK: - Errors

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

// MARK: - Keychain Helper

class KeychainHelper {
    static func save(key: String, data: String) {
        let data = data.data(using: .utf8)!

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data
        ]

        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }

    static func load(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true
        ]

        var result: AnyObject?
        SecItemCopyMatching(query as CFDictionary, &result)

        guard let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]

        SecItemDelete(query as CFDictionary)
    }
}
```

### SwiftUI Views

#### Phone Number Entry

```swift
import SwiftUI

struct PhoneNumberEntryView: View {
    @StateObject private var viewModel = PhoneNumberViewModel()
    @State private var navigateToVerification = false

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Spacer()

                Image(systemName: "phone.circle.fill")
                    .font(.system(size: 80))
                    .foregroundColor(.blue)

                Text("Enter Your Phone Number")
                    .font(.title2)
                    .bold()

                Text("We'll send you a verification code")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                TextField("Phone Number", text: $viewModel.phoneNumber)
                    .keyboardType(.phonePad)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .padding(.horizontal, 40)
                    .font(.title3)

                if let error = viewModel.errorMessage {
                    Text(error)
                        .foregroundColor(.red)
                        .font(.caption)
                }

                Button(action: {
                    Task {
                        await viewModel.sendVerificationCode()
                        if viewModel.codeSent {
                            navigateToVerification = true
                        }
                    }
                }) {
                    if viewModel.isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    } else {
                        Text("Send Code")
                            .fontWeight(.semibold)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(viewModel.isValidPhoneNumber ? Color.blue : Color.gray)
                .foregroundColor(.white)
                .cornerRadius(10)
                .padding(.horizontal, 40)
                .disabled(!viewModel.isValidPhoneNumber || viewModel.isLoading)

                Spacer()

                NavigationLink(destination: VerificationCodeView(), isActive: $navigateToVerification) {
                    EmptyView()
                }
            }
            .navigationTitle("Sign In")
        }
    }
}

class PhoneNumberViewModel: ObservableObject {
    @Published var phoneNumber = ""
    @Published var errorMessage: String?
    @Published var isLoading = false
    @Published var codeSent = false

    var isValidPhoneNumber: Bool {
        let cleaned = phoneNumber.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
        return cleaned.count >= 10
    }

    func sendVerificationCode() async {
        errorMessage = nil
        isLoading = true

        do {
            try await AuthenticationService.shared.sendVerificationCode(phoneNumber: phoneNumber)
            await MainActor.run {
                codeSent = true
                isLoading = false
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }
}
```

#### Verification Code Entry

```swift
import SwiftUI

struct VerificationCodeView: View {
    @StateObject private var viewModel = VerificationViewModel()
    @Environment(\.presentationMode) var presentationMode

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "envelope.circle.fill")
                .font(.system(size: 80))
                .foregroundColor(.green)

            Text("Enter Verification Code")
                .font(.title2)
                .bold()

            if let phoneNumber = AuthenticationService.shared.phoneNumber {
                Text("Sent to \(phoneNumber)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 10) {
                ForEach(0..<6, id: \.self) { index in
                    CodeDigitView(digit: viewModel.getDigit(at: index))
                }
            }
            .padding(.horizontal, 40)

            TextField("", text: $viewModel.code)
                .keyboardType(.numberPad)
                .opacity(0)
                .frame(height: 0)

            if let error = viewModel.errorMessage {
                Text(error)
                    .foregroundColor(.red)
                    .font(.caption)
            }

            Button(action: {
                Task {
                    await viewModel.verifyCode()
                }
            }) {
                if viewModel.isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                } else {
                    Text("Verify")
                        .fontWeight(.semibold)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(viewModel.code.count == 6 ? Color.blue : Color.gray)
            .foregroundColor(.white)
            .cornerRadius(10)
            .padding(.horizontal, 40)
            .disabled(viewModel.code.count != 6 || viewModel.isLoading)

            Button("Resend Code") {
                Task {
                    await viewModel.resendCode()
                }
            }
            .foregroundColor(.blue)

            Spacer()
        }
        .navigationTitle("Verification")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct CodeDigitView: View {
    let digit: String?

    var body: some View {
        Text(digit ?? "")
            .font(.title)
            .frame(width: 45, height: 55)
            .background(Color.gray.opacity(0.1))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(digit != nil ? Color.blue : Color.gray.opacity(0.3), lineWidth: 2)
            )
    }
}

class VerificationViewModel: ObservableObject {
    @Published var code = ""
    @Published var errorMessage: String?
    @Published var isLoading = false

    func getDigit(at index: Int) -> String? {
        guard index < code.count else { return nil }
        let digitIndex = code.index(code.startIndex, offsetBy: index)
        return String(code[digitIndex])
    }

    func verifyCode() async {
        errorMessage = nil
        isLoading = true

        do {
            _ = try await AuthenticationService.shared.verifyCode(code)
            // Navigate to main app
            await MainActor.run {
                isLoading = false
                NotificationCenter.default.post(name: .userDidAuthenticate, object: nil)
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }

    func resendCode() async {
        guard let phoneNumber = AuthenticationService.shared.phoneNumber else { return }

        do {
            try await AuthenticationService.shared.sendVerificationCode(phoneNumber: phoneNumber)
            await MainActor.run {
                code = ""
                errorMessage = nil
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
            }
        }
    }
}

extension Notification.Name {
    static let userDidAuthenticate = Notification.Name("userDidAuthenticate")
}
```

## Security Considerations

### 1. Rate Limiting

Implement rate limiting on the backend:

```javascript
const rateLimit = require('express-rate-limit');

const sendCodeLimiter = rateLimit({
    windowMs: 15 * 60 * 1000, // 15 minutes
    max: 5, // 5 requests per window
    message: 'Too many verification requests, please try again later'
});

router.post('/send-code', sendCodeLimiter, async (req, res) => {
    // ...
});
```

### 2. Token Security

- Store tokens in Keychain (iOS)
- Use HTTPS only
- Short token expiration (30 days)
- Implement token refresh
- Revoke tokens on logout

### 3. Phone Number Validation

- Normalize to E.164 format
- Validate format before sending
- Check against known valid formats
- Implement country code support

### 4. OTP Security

- 6-digit codes minimum
- Short expiration (5-10 minutes)
- Limit verification attempts
- Use secure random generation
- One-time use only

## Alternative: Firebase Authentication

For faster implementation, consider Firebase Auth:

```swift
import FirebaseAuth

func sendVerificationCode(phoneNumber: String) {
    PhoneAuthProvider.provider().verifyPhoneNumber(phoneNumber, uiDelegate: nil) { verificationID, error in
        if let error = error {
            print("Error: \(error.localizedDescription)")
            return
        }

        UserDefaults.standard.set(verificationID, forKey: "authVerificationID")
    }
}

func verifyCode(_ code: String) {
    guard let verificationID = UserDefaults.standard.string(forKey: "authVerificationID") else { return }

    let credential = PhoneAuthProvider.provider().credential(
        withVerificationID: verificationID,
        verificationCode: code
    )

    Auth.auth().signIn(with: credential) { authResult, error in
        if let error = error {
            print("Error: \(error.localizedDescription)")
            return
        }

        // User signed in
    }
}
```

## Best Practices

1. **User Experience**
   - Auto-detect phone number from SIM
   - Auto-fill verification codes (iOS 12+)
   - Clear error messages
   - Resend code option

2. **Security**
   - Always use HTTPS
   - Rate limit requests
   - Log authentication attempts
   - Monitor for fraud

3. **Reliability**
   - Handle network errors gracefully
   - Implement retry logic
   - Provide alternative verification methods
   - Support multiple regions

4. **Privacy**
   - Don't store plain phone numbers unnecessarily
   - Hash sensitive data
   - Comply with local regulations
   - Provide data deletion options

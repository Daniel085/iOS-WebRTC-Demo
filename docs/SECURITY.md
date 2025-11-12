# Security Considerations and Best Practices

## Overview

Security is paramount in a VoIP application handling personal communications. This document outlines security considerations, threats, and best practices.

## Security Principles

### 1. Defense in Depth
Multiple layers of security to protect against failures in any single layer.

### 2. Principle of Least Privilege
Users and services have only the minimum permissions necessary.

### 3. Fail Secure
System defaults to secure state on failure.

### 4. Privacy by Design
Privacy considerations integrated from the start.

## Threat Model

### Threats to Consider

1. **Man-in-the-Middle (MITM) Attacks**
   - Intercepting signaling messages
   - Intercepting media streams
   - Impersonating users

2. **Unauthorized Access**
   - Account takeover
   - Device theft
   - Token theft

3. **Denial of Service (DoS)**
   - Overwhelming signaling server
   - Excessive API calls
   - Resource exhaustion

4. **Data Breaches**
   - User data exposure
   - Call metadata leaks
   - Contact information leaks

5. **Social Engineering**
   - Phishing attacks
   - Fake verification codes
   - Impersonation

## Security Layers

### 1. Transport Security

#### HTTPS/WSS Everywhere

```swift
// Enforce HTTPS
func validateURL(_ url: URL) -> Bool {
    guard url.scheme == "https" || url.scheme == "wss" else {
        print("Insecure scheme detected: \(url.scheme ?? "none")")
        return false
    }
    return true
}
```

#### Certificate Pinning

```swift
import Foundation

class CertificatePinner: NSObject, URLSessionDelegate {

    private let certificates: [Data]

    init(certificates: [Data]) {
        self.certificates = certificates
    }

    func urlSession(_ session: URLSession,
                   didReceive challenge: URLAuthenticationChallenge,
                   completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {

        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let serverTrust = challenge.protectionSpace.serverTrust else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        // Validate certificate
        if validateServerTrust(serverTrust) {
            let credential = URLCredential(trust: serverTrust)
            completionHandler(.useCredential, credential)
        } else {
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }

    private func validateServerTrust(_ serverTrust: SecTrust) -> Bool {
        // Validate against pinned certificates
        guard let serverCertificate = SecTrustGetCertificateAtIndex(serverTrust, 0) else {
            return false
        }

        let serverCertificateData = SecCertificateCopyData(serverCertificate) as Data

        for pinnedCertificate in certificates {
            if serverCertificateData == pinnedCertificate {
                return true
            }
        }

        return false
    }
}
```

#### TLS 1.3 Enforcement

```javascript
// Backend: Enforce TLS 1.3
const options = {
    key: fs.readFileSync('server-key.pem'),
    cert: fs.readFileSync('server-cert.pem'),
    minVersion: 'TLSv1.3',
    ciphers: [
        'TLS_AES_256_GCM_SHA384',
        'TLS_AES_128_GCM_SHA256'
    ].join(':')
};

https.createServer(options, app);
```

### 2. Authentication Security

#### Secure Token Storage

```swift
import Security

class SecureStorage {

    static func saveToken(_ token: String, for key: String) {
        guard let data = token.data(using: .utf8) else { return }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
            kSecValueData as String: data
        ]

        // Delete existing
        SecItemDelete(query as CFDictionary)

        // Add new
        let status = SecItemAdd(query as CFDictionary, nil)

        if status != errSecSuccess {
            print("Keychain save failed: \(status)")
        }
    }

    static func loadToken(for key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let token = String(data: data, encoding: .utf8) else {
            return nil
        }

        return token
    }

    static func deleteToken(for key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]

        SecItemDelete(query as CFDictionary)
    }
}
```

#### JWT Token Best Practices

```javascript
// Backend: Secure JWT generation
const jwt = require('jsonwebtoken');
const crypto = require('crypto');

// Strong secret (256 bits minimum)
const JWT_SECRET = process.env.JWT_SECRET || crypto.randomBytes(32).toString('hex');

function generateToken(userId, phoneNumber) {
    return jwt.sign(
        {
            userId,
            phoneNumber,
            iat: Math.floor(Date.now() / 1000),
            jti: crypto.randomUUID() // Unique token ID
        },
        JWT_SECRET,
        {
            algorithm: 'HS256',
            expiresIn: '30d',
            issuer: 'com.yourapp.api',
            audience: 'com.yourapp.ios'
        }
    );
}

function verifyToken(token) {
    try {
        return jwt.verify(token, JWT_SECRET, {
            algorithms: ['HS256'],
            issuer: 'com.yourapp.api',
            audience: 'com.yourapp.ios'
        });
    } catch (error) {
        console.error('Token verification failed:', error.message);
        return null;
    }
}
```

#### Rate Limiting

```javascript
const rateLimit = require('express-rate-limit');
const RedisStore = require('rate-limit-redis');
const redis = require('redis');

const redisClient = redis.createClient();

// Authentication endpoints
const authLimiter = rateLimit({
    store: new RedisStore({
        client: redisClient,
        prefix: 'rate-limit:auth:'
    }),
    windowMs: 15 * 60 * 1000, // 15 minutes
    max: 5, // 5 attempts per window
    message: 'Too many authentication attempts, please try again later',
    standardHeaders: true,
    legacyHeaders: false
});

app.use('/auth', authLimiter);

// API endpoints
const apiLimiter = rateLimit({
    store: new RedisStore({
        client: redisClient,
        prefix: 'rate-limit:api:'
    }),
    windowMs: 1 * 60 * 1000, // 1 minute
    max: 100, // 100 requests per minute
    standardHeaders: true,
    legacyHeaders: false
});

app.use('/api', apiLimiter);
```

### 3. Media Encryption

#### WebRTC DTLS-SRTP

WebRTC provides built-in encryption:
- DTLS (Datagram Transport Layer Security) for key exchange
- SRTP (Secure Real-time Transport Protocol) for media

```swift
// Ensure DTLS is enabled (default in WebRTC)
let constraints = RTCMediaConstraints(
    mandatoryConstraints: [
        "DtlsSrtpKeyAgreement": "true"
    ],
    optionalConstraints: nil
)
```

#### Verify Encryption

```swift
extension WebRTCClient: RTCPeerConnectionDelegate {
    func peerConnection(_ peerConnection: RTCPeerConnection,
                       didChange state: RTCPeerConnectionState) {

        if state == .connected {
            // Verify DTLS connection
            peerConnection.statistics { report in
                for (_, stats) in report.statistics {
                    if stats.type == "transport" {
                        if let dtlsState = stats.values["dtlsState"] as? String {
                            print("DTLS State: \(dtlsState)")
                            // Should be "connected"
                        }

                        if let srtpCipher = stats.values["srtpCipher"] as? String {
                            print("SRTP Cipher: \(srtpCipher)")
                            // Verify strong cipher
                        }
                    }
                }
            }
        }
    }
}
```

### 4. Signaling Security

#### WebSocket Authentication

```swift
// iOS: Authenticate WebSocket
func connect() {
    guard let token = AuthenticationService.shared.authToken else {
        print("No auth token available")
        return
    }

    socket.connect(withPayload: ["token": token])
}

socket.on(clientEvent: .error) { data, ack in
    print("WebSocket error: \(data)")
    // Handle unauthorized error - refresh token or re-authenticate
}
```

```javascript
// Backend: Validate WebSocket connections
io.use((socket, next) => {
    const token = socket.handshake.auth.token;

    if (!token) {
        return next(new Error('Authentication required'));
    }

    const decoded = verifyToken(token);

    if (!decoded) {
        return next(new Error('Invalid token'));
    }

    socket.userId = decoded.userId;
    socket.phoneNumber = decoded.phoneNumber;

    next();
});
```

#### Message Validation

```javascript
// Validate all incoming messages
socket.on('call-initiate', (data) => {
    // Input validation
    if (!data.to || !data.callId || typeof data.hasVideo !== 'boolean') {
        socket.emit('error', {
            code: 'INVALID_INPUT',
            message: 'Invalid call initiation data'
        });
        return;
    }

    // Validate phone number format
    if (!isValidPhoneNumber(data.to)) {
        socket.emit('error', {
            code: 'INVALID_PHONE_NUMBER',
            message: 'Invalid recipient phone number'
        });
        return;
    }

    // Validate UUID
    if (!isValidUUID(data.callId)) {
        socket.emit('error', {
            code: 'INVALID_CALL_ID',
            message: 'Invalid call ID format'
        });
        return;
    }

    // Prevent self-calling
    if (data.to === socket.phoneNumber) {
        socket.emit('error', {
            code: 'SELF_CALL',
            message: 'Cannot call yourself'
        });
        return;
    }

    // Process call
    handleCallInitiation(socket, data);
});
```

### 5. Data Privacy

#### Minimize Data Collection

```javascript
// Only store necessary data
const userSchema = new Schema({
    phoneNumber: {
        type: String,
        required: true,
        unique: true
    },
    // Hash phone number for lookups
    phoneNumberHash: {
        type: String,
        required: true,
        index: true
    },
    createdAt: Date,
    lastActive: Date
    // DON'T store: contacts, call content, location, etc.
});

// Hash phone number
function hashPhoneNumber(phoneNumber) {
    return crypto
        .createHash('sha256')
        .update(phoneNumber + process.env.HASH_SALT)
        .digest('hex');
}
```

#### Call Metadata

```javascript
// Minimal call metadata
const callLogSchema = new Schema({
    callId: String,
    participants: [String], // Hashed phone numbers
    startTime: Date,
    endTime: Date,
    duration: Number,
    // DON'T store: call content, location, detailed connection info
});

// Auto-delete old records
callLogSchema.index(
    { endTime: 1 },
    { expireAfterSeconds: 30 * 24 * 60 * 60 } // 30 days
);
```

#### GDPR Compliance

```javascript
// User data deletion
async function deleteUserData(userId) {
    await Promise.all([
        User.deleteOne({ _id: userId }),
        CallLog.deleteMany({ participants: userId }),
        Device.deleteMany({ userId })
    ]);

    // Notify other services
    await notifyDataDeletion(userId);
}

// Data export
async function exportUserData(userId) {
    const user = await User.findById(userId);
    const callLogs = await CallLog.find({ participants: userId });

    return {
        profile: {
            phoneNumber: user.phoneNumber,
            createdAt: user.createdAt
        },
        callHistory: callLogs.map(log => ({
            date: log.startTime,
            duration: log.duration
        }))
    };
}
```

### 6. Input Validation

#### Phone Number Validation

```swift
func validatePhoneNumber(_ phoneNumber: String) -> Bool {
    // Use PhoneNumberKit for proper validation
    let phoneNumberKit = PhoneNumberKit()

    do {
        let parsed = try phoneNumberKit.parse(phoneNumber)
        return phoneNumberKit.isValidPhoneNumber(phoneNumber)
    } catch {
        return false
    }
}
```

#### Sanitize User Input

```javascript
const validator = require('validator');

function sanitizeInput(input) {
    // Escape HTML
    let clean = validator.escape(input);

    // Trim whitespace
    clean = clean.trim();

    // Limit length
    if (clean.length > 1000) {
        clean = clean.substring(0, 1000);
    }

    return clean;
}
```

### 7. Secure Communication Patterns

#### Avoid Timing Attacks

```javascript
const crypto = require('crypto');

function constantTimeCompare(a, b) {
    if (a.length !== b.length) {
        return false;
    }

    return crypto.timingSafeEqual(
        Buffer.from(a),
        Buffer.from(b)
    );
}

// Use for comparing tokens, hashes, etc.
function verifyToken(provided, expected) {
    return constantTimeCompare(provided, expected);
}
```

#### Prevent CSRF

```javascript
const csrf = require('csurf');

// Enable CSRF protection for web endpoints
app.use(csrf({ cookie: true }));

app.post('/api/call', (req, res) => {
    // Token automatically validated
    // ...
});
```

## Security Monitoring

### Logging

```javascript
const winston = require('winston');

const logger = winston.createLogger({
    level: 'info',
    format: winston.format.json(),
    transports: [
        new winston.transports.File({ filename: 'error.log', level: 'error' }),
        new winston.transports.File({ filename: 'combined.log' })
    ]
});

// Log security events
function logSecurityEvent(event, details) {
    logger.warn('Security Event', {
        event,
        timestamp: new Date(),
        ...details
    });
}

// Examples
logSecurityEvent('failed_authentication', { phoneNumber, attempts });
logSecurityEvent('rate_limit_exceeded', { ip, endpoint });
logSecurityEvent('invalid_token', { userId, ip });
```

### Intrusion Detection

```javascript
// Track failed authentication attempts
const failedAttempts = new Map();

function trackFailedAttempt(phoneNumber, ip) {
    const key = `${phoneNumber}:${ip}`;
    const attempts = failedAttempts.get(key) || 0;

    failedAttempts.set(key, attempts + 1);

    if (attempts > 10) {
        // Alert security team
        alertSecurityTeam({
            type: 'brute_force_attempt',
            phoneNumber,
            ip,
            attempts
        });

        // Temporarily block
        blockIP(ip, 60 * 60); // 1 hour
    }
}
```

## Incident Response

### Security Incident Plan

1. **Detection**
   - Monitor logs for anomalies
   - Alert on suspicious patterns
   - User reports

2. **Assessment**
   - Determine severity
   - Identify affected users
   - Assess data exposure

3. **Containment**
   - Revoke compromised tokens
   - Block malicious IPs
   - Disable affected accounts

4. **Eradication**
   - Patch vulnerabilities
   - Update dependencies
   - Fix security holes

5. **Recovery**
   - Restore services
   - Notify affected users
   - Implement additional monitoring

6. **Lessons Learned**
   - Document incident
   - Update procedures
   - Improve defenses

### Token Revocation

```javascript
// Maintain blacklist of revoked tokens
const revokedTokens = new Set();

function revokeToken(tokenId) {
    revokedTokens.add(tokenId);

    // Persist to database
    RevokedToken.create({
        tokenId,
        revokedAt: new Date()
    });
}

function isTokenRevoked(tokenId) {
    return revokedTokens.has(tokenId);
}

// Check in middleware
function authenticateToken(req, res, next) {
    const token = extractToken(req);
    const decoded = verifyToken(token);

    if (!decoded || isTokenRevoked(decoded.jti)) {
        return res.status(401).json({ error: 'Token revoked' });
    }

    req.user = decoded;
    next();
}
```

## Security Checklist

### iOS Application

- [ ] All network traffic over HTTPS/WSS
- [ ] Certificate pinning implemented
- [ ] Auth tokens stored in Keychain
- [ ] Sensitive data not logged
- [ ] Jailbreak detection (optional)
- [ ] Input validation on all user input
- [ ] WebRTC encryption verified
- [ ] No hardcoded secrets
- [ ] Obfuscate API keys
- [ ] Regular dependency updates

### Backend

- [ ] TLS 1.3 enforced
- [ ] Strong JWT secrets
- [ ] Rate limiting on all endpoints
- [ ] Input validation and sanitization
- [ ] SQL injection prevention
- [ ] XSS prevention
- [ ] CSRF protection
- [ ] Proper CORS configuration
- [ ] Security headers configured
- [ ] Regular security audits
- [ ] Dependency vulnerability scanning
- [ ] Logging and monitoring
- [ ] Incident response plan

### DevOps

- [ ] Secrets in environment variables
- [ ] No secrets in version control
- [ ] Production database encrypted
- [ ] Regular backups
- [ ] Backup encryption
- [ ] Network segmentation
- [ ] Firewall rules configured
- [ ] DDoS protection
- [ ] Regular penetration testing
- [ ] Security patch management

## Compliance

### App Store Requirements

- Privacy policy URL
- Data collection transparency
- Permission explanations
- CallKit proper use
- VoIP push proper use

### GDPR (if applicable)

- User data export
- Right to deletion
- Consent for data processing
- Data processing records
- Privacy by design

### CCPA (if applicable)

- Privacy policy disclosure
- Opt-out mechanism
- Data sale disclosure

## Resources

- [OWASP Mobile Security Project](https://owasp.org/www-project-mobile-security/)
- [Apple Security Guide](https://support.apple.com/guide/security/welcome/web)
- [WebRTC Security](https://webrtc-security.github.io/)
- [NIST Cybersecurity Framework](https://www.nist.gov/cyberframework)

## Regular Security Tasks

### Weekly
- Review security logs
- Check for failed auth attempts
- Monitor rate limit hits

### Monthly
- Update dependencies
- Review access controls
- Test backups

### Quarterly
- Security audit
- Penetration testing
- Review incident response plan

### Annually
- Comprehensive security review
- Third-party security audit
- Update security policies

# VoIP Push Notifications

## Overview

VoIP (Voice over IP) push notifications are a special type of Apple Push Notification that allows your app to be woken up in the background (even when terminated) to handle incoming calls. This enables the native CallKit incoming call experience.

## Why VoIP Push Notifications?

### Regular Push Notifications vs VoIP Push

| Feature | Regular Push | VoIP Push |
|---------|-------------|-----------|
| Wake app when terminated | No | Yes |
| Guaranteed delivery | No | Yes |
| Unlimited payload | No | Yes (4KB) |
| No user notification required | No | Yes |
| Low latency | Standard | High priority |
| Background execution time | Limited | Extended |
| Must show CallKit UI | No | Yes (required) |

### Requirements

- iOS 8.0+
- Valid APNs certificate or key
- PushKit framework
- Must report to CallKit when received
- Cannot be used for non-VoIP purposes (App Store rejection)

## iOS Implementation

### 1. Enable VoIP Push Capability

In Xcode:
1. Select your target
2. Go to "Signing & Capabilities"
3. Click "+ Capability"
4. Add "Background Modes"
5. Check "Voice over IP"

### 2. PushKit Integration

```swift
import PushKit

class VoIPPushManager: NSObject {

    static let shared = VoIPPushManager()

    private let voipRegistry: PKPushRegistry
    var deviceToken: String?

    private override init() {
        self.voipRegistry = PKPushRegistry(queue: DispatchQueue.main)
        super.init()

        voipRegistry.delegate = self
        voipRegistry.desiredPushTypes = [.voIP]
    }

    func registerForVoIPPushes() {
        voipRegistry.desiredPushTypes = [.voIP]
    }
}

// MARK: - PKPushRegistryDelegate

extension VoIPPushManager: PKPushRegistryDelegate {

    // Called when device token is updated
    func pushRegistry(_ registry: PKPushRegistry,
                     didUpdate pushCredentials: PKPushCredentials,
                     for type: PKPushType) {

        guard type == .voIP else { return }

        let token = pushCredentials.token.map { String(format: "%02x", $0) }.joined()
        print("VoIP token: \(token)")

        self.deviceToken = token

        // Send token to your server
        Task {
            await uploadDeviceToken(token)
        }
    }

    // Called when VoIP push is received
    func pushRegistry(_ registry: PKPushRegistry,
                     didReceiveIncomingPushWith payload: PKPushPayload,
                     for type: PKPushType,
                     completion: @escaping () -> Void) {

        guard type == .voIP else {
            completion()
            return
        }

        print("VoIP push received: \(payload.dictionaryPayload)")

        // Extract call information
        guard let callIdString = payload.dictionaryPayload["callId"] as? String,
              let callId = UUID(uuidString: callIdString),
              let callerNumber = payload.dictionaryPayload["caller"] as? String,
              let hasVideo = payload.dictionaryPayload["hasVideo"] as? Bool else {
            print("Invalid VoIP payload")
            completion()
            return
        }

        let callerName = payload.dictionaryPayload["callerName"] as? String

        // Report incoming call to CallKit
        CallKitManager.shared.reportIncomingCall(
            uuid: callId,
            phoneNumber: callerNumber,
            hasVideo: hasVideo
        ) { error in
            if let error = error {
                print("Error reporting call: \(error)")
            }
            completion()
        }
    }

    func pushRegistry(_ registry: PKPushRegistry,
                     didInvalidatePushTokenFor type: PKPushType) {
        print("VoIP token invalidated")
        self.deviceToken = nil
    }

    // MARK: - Private Methods

    private func uploadDeviceToken(_ token: String) async {
        guard let authToken = AuthenticationService.shared.authToken else {
            print("Not authenticated, cannot upload device token")
            return
        }

        guard let url = URL(string: "https://your-api.com/device/register") else {
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")

        let body: [String: Any] = [
            "deviceToken": token,
            "platform": "ios"
        ]

        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (_, response) = try await URLSession.shared.data(for: request)

            if let httpResponse = response as? HTTPURLResponse,
               httpResponse.statusCode == 200 {
                print("Device token uploaded successfully")

                // Store locally
                UserDefaults.standard.set(token, forKey: "voipDeviceToken")
            }
        } catch {
            print("Error uploading device token: \(error)")
        }
    }
}
```

### 3. App Delegate Setup

```swift
import UIKit

@main
class AppDelegate: UIResponder, UIApplicationDelegate {

    func application(_ application: UIApplication,
                    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {

        // Register for VoIP pushes
        VoIPPushManager.shared.registerForVoIPPushes()

        return true
    }
}
```

### 4. Handling Background Launch

```swift
// When app is launched from VoIP push
func application(_ application: UIApplication,
                didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {

    // Check if launched from VoIP push
    if let remoteNotification = launchOptions?[.remoteNotification] as? [String: Any] {
        print("Launched from VoIP push")
        // Handle the call
    }

    return true
}
```

## Backend Implementation (Node.js)

### 1. Setup APNs Connection

```javascript
// apns-service.js
const apn = require('apn');

class APNsService {
    constructor() {
        // Using token-based authentication (recommended)
        this.provider = new apn.Provider({
            token: {
                key: process.env.APN_KEY_PATH || './AuthKey_XXXXXXXXXX.p8',
                keyId: process.env.APN_KEY_ID,
                teamId: process.env.APN_TEAM_ID
            },
            production: process.env.NODE_ENV === 'production'
        });
    }

    async sendVoIPPush(deviceToken, payload) {
        const notification = new apn.Notification({
            topic: process.env.VOIP_BUNDLE_ID + '.voip', // e.g., 'com.yourapp.dialer.voip'
            payload: {
                callId: payload.callId,
                caller: payload.caller,
                callerName: payload.callerName,
                hasVideo: payload.hasVideo
            },
            pushType: 'voip',
            priority: 10, // High priority
            expiry: Math.floor(Date.now() / 1000) + 60 // 1 minute expiry
        });

        try {
            const result = await this.provider.send(notification, deviceToken);

            if (result.failed.length > 0) {
                console.error('VoIP push failed:', result.failed);
                return { success: false, error: result.failed[0].response };
            }

            console.log('VoIP push sent successfully:', result.sent);
            return { success: true };
        } catch (error) {
            console.error('Error sending VoIP push:', error);
            return { success: false, error: error.message };
        }
    }

    shutdown() {
        this.provider.shutdown();
    }
}

module.exports = new APNsService();
```

### 2. Device Token Registration

```javascript
// routes/device.js
const express = require('express');
const router = express.Router();
const db = require('../database');

router.post('/register', authenticateToken, async (req, res) => {
    const { deviceToken, platform } = req.body;
    const { userId } = req.user;

    if (!deviceToken || platform !== 'ios') {
        return res.status(400).json({
            success: false,
            error: 'Invalid request'
        });
    }

    try {
        // Store device token
        await db.devices.upsert({
            userId,
            deviceToken,
            platform,
            updatedAt: new Date()
        });

        res.json({ success: true });
    } catch (error) {
        console.error('Error registering device:', error);
        res.status(500).json({
            success: false,
            error: 'Server error'
        });
    }
});

module.exports = router;
```

### 3. Sending VoIP Push from Signaling Server

```javascript
// In signaling server when call is initiated
socket.on('call-initiate', async (data) => {
    const { to, callId, hasVideo } = data;
    const from = socket.phoneNumber;

    // Check if recipient is connected
    const recipient = connectedUsers.get(to);

    if (!recipient) {
        // Recipient offline - send VoIP push
        const device = await db.devices.findOne({
            where: { userId: to }
        });

        if (device && device.deviceToken) {
            const callerName = await lookupContactName(from);

            await apnsService.sendVoIPPush(device.deviceToken, {
                callId,
                caller: from,
                callerName,
                hasVideo
            });

            console.log(`VoIP push sent to ${to}`);
        } else {
            socket.emit('error', {
                code: 'USER_UNAVAILABLE',
                message: 'User is not available'
            });
            return;
        }
    } else {
        // Recipient online - use WebSocket
        io.to(recipient.socketId).emit('incoming-call', {
            callId,
            from,
            hasVideo
        });
    }
});
```

## Creating APNs Certificates/Keys

### Method 1: Token-Based Authentication (Recommended)

1. **Go to Apple Developer Portal**
   - Navigate to Certificates, Identifiers & Profiles
   - Click on "Keys"
   - Click "+" to create a new key

2. **Create APNs Key**
   - Name: "VoIP Push Key"
   - Check "Apple Push Notifications service (APNs)"
   - Click "Continue" and "Register"
   - Download the .p8 file (can only download once!)

3. **Note Important Values**
   - Key ID (shown in portal)
   - Team ID (in membership section)
   - Key file path

4. **Configure in Backend**
   ```javascript
   token: {
       key: './AuthKey_XXXXXXXXXX.p8',
       keyId: 'XXXXXXXXXX',
       teamId: 'XXXXXXXXXX'
   }
   ```

### Method 2: Certificate-Based (Legacy)

1. Create Certificate Signing Request (CSR) on Mac
2. Upload CSR to Apple Developer Portal
3. Download VoIP Services Certificate
4. Convert to .p12 format
5. Use in APNs configuration

**Note**: Token-based is preferred as it doesn't expire yearly.

## Testing VoIP Push Notifications

### 1. Using Pusher App (macOS)

1. Download [Pusher](https://github.com/noodlewerk/NWPusher)
2. Select your .p8 key or .p12 certificate
3. Enter device token
4. Set topic to `com.yourapp.voip`
5. Create JSON payload:
   ```json
   {
       "callId": "12345678-1234-1234-1234-123456789012",
       "caller": "+15551234567",
       "hasVideo": true
   }
   ```
6. Send push

### 2. Using curl

```bash
# Generate JWT token for authentication
# (See script below)

curl -v \
  -H "authorization: bearer $JWT_TOKEN" \
  -H "apns-topic: com.yourapp.voip" \
  -H "apns-push-type: voip" \
  -H "apns-priority: 10" \
  -d '{"callId":"12345","caller":"+15551234567","hasVideo":true}' \
  --http2 \
  https://api.sandbox.push.apple.com/3/device/$DEVICE_TOKEN
```

### 3. JWT Token Generation Script

```javascript
// generate-jwt.js
const jwt = require('jsonwebtoken');
const fs = require('fs');

const authKey = fs.readFileSync('./AuthKey_XXXXXXXXXX.p8', 'utf8');
const keyId = 'XXXXXXXXXX';
const teamId = 'XXXXXXXXXX';

const token = jwt.sign(
    {
        iss: teamId,
        iat: Math.floor(Date.now() / 1000)
    },
    authKey,
    {
        algorithm: 'ES256',
        header: {
            alg: 'ES256',
            kid: keyId
        }
    }
);

console.log(token);
```

## Important Considerations

### 1. App Store Requirements

**CRITICAL**: Misuse of VoIP pushes will result in App Store rejection.

✅ **Allowed:**
- Incoming call notifications
- Reporting calls to CallKit

❌ **Not Allowed:**
- General notifications
- Silent data updates
- Waking app for non-call purposes
- Not showing CallKit UI

### 2. Best Practices

```swift
func pushRegistry(_ registry: PKPushRegistry,
                 didReceiveIncomingPushWith payload: PKPushPayload,
                 for type: PKPushType,
                 completion: @escaping () -> Void) {

    // ✅ ALWAYS report to CallKit
    CallKitManager.shared.reportIncomingCall(...)

    // ❌ NEVER ignore VoIP push without reporting call
    // completion() // This alone will get you rejected

    // ✅ ALWAYS call completion handler
    completion()
}
```

### 3. Handling Failures

```swift
func reportIncomingCall(uuid: UUID, phoneNumber: String, hasVideo: Bool) {
    let update = CXCallUpdate()
    update.remoteHandle = CXHandle(type: .phoneNumber, value: phoneNumber)
    update.hasVideo = hasVideo

    provider.reportNewIncomingCall(with: uuid, update: update) { error in
        if let error = error as? CXErrorCodeIncomingCallError {
            switch error.code {
            case .unknown:
                print("Unknown error")
            case .unentitled:
                print("App not entitled for CallKit")
            case .callUUIDAlreadyExists:
                print("Call with this UUID already exists")
            case .filteredByDoNotDisturb:
                print("Filtered by Do Not Disturb")
            case .filteredByBlockList:
                print("Caller is blocked")
            @unknown default:
                print("Unknown error code")
            }
        }

        // Even if error, you MUST have attempted to report
        completion()
    }
}
```

### 4. Debugging

Enable verbose logging:

```swift
// Check if VoIP push was received
func pushRegistry(_ registry: PKPushRegistry,
                 didReceiveIncomingPushWith payload: PKPushPayload,
                 for type: PKPushType,
                 completion: @escaping () -> Void) {

    print("=== VoIP Push Received ===")
    print("Payload: \(payload.dictionaryPayload)")
    print("Type: \(type)")
    print("========================")

    // ... rest of implementation
}
```

Check device console in Xcode for push delivery.

### 5. Production Checklist

- [ ] Using production APNs environment
- [ ] Valid production certificate/key
- [ ] Correct bundle ID + .voip suffix
- [ ] VoIP capability enabled in app
- [ ] Always reporting to CallKit
- [ ] Handling completion properly
- [ ] Testing with terminated app
- [ ] Testing with Do Not Disturb
- [ ] Monitoring failed pushes
- [ ] Token refresh on invalidation

## Troubleshooting

### Push Not Received

1. **Check device token**
   - Verify token is uploaded to server
   - Ensure it's not nil or empty

2. **Check APNs configuration**
   - Verify key ID, team ID, key file
   - Ensure using correct environment (dev/prod)
   - Check topic matches bundle ID + .voip

3. **Check app state**
   - VoIP pushes work even when app terminated
   - But first registration requires app launch

4. **Check payload**
   - Must be valid JSON
   - Size limit: 4KB
   - No aps dictionary needed for VoIP

### CallKit UI Not Showing

1. **Verify VoIP push calls CallKit**
   ```swift
   provider.reportNewIncomingCall(with: uuid, update: update)
   ```

2. **Check for errors**
   - Do Not Disturb can block
   - Blocked numbers don't show
   - Invalid UUID format

3. **Verify completion handler**
   - Must be called within limited time
   - Don't perform async operations before calling

### Token Invalidation

Tokens can be invalidated when:
- User uninstalls app
- User restores device
- App is updated
- System resets token

Always handle `didInvalidatePushTokenFor` and re-register.

## Sample Complete Flow

```
1. User A opens app
   → Registers for VoIP pushes
   → Receives device token
   → Uploads to server

2. User A closes app (or force quits)

3. User B initiates call to User A
   → Signaling server checks User A status
   → User A offline
   → Server sends VoIP push

4. iOS delivers VoIP push to User A's device
   → Wakes app in background
   → Calls pushRegistry delegate

5. App reports incoming call to CallKit
   → CallKit shows native incoming call UI
   → User sees call on lock screen

6. User A answers call
   → CallKit notifies app
   → App connects to signaling server
   → WebRTC connection established
```

## Code Organization

Recommended file structure:

```
/Services
  /VoIP
    VoIPPushManager.swift      // PushKit management
  /CallKit
    CallKitManager.swift        // CallKit management
  /Signaling
    SignalingClient.swift       // WebSocket signaling
  /WebRTC
    WebRTCClient.swift          // WebRTC peer connections

/Models
  Call.swift                     // Call data model
```

## Summary

VoIP push notifications are essential for a native calling experience on iOS. They enable:
- Background app wakeup
- Native CallKit incoming call UI
- Professional UX matching system Phone app

Key requirements:
- Must use PushKit framework
- Must report all VoIP pushes to CallKit
- Cannot be used for non-VoIP purposes
- Must call completion handler promptly

When implemented correctly, users get a seamless experience identical to regular phone calls.

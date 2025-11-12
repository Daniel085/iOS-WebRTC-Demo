# How It Works - Complete Technical Walkthrough

This document explains exactly how the iOS WebRTC Dialer application works, from opening the app to making calls.

## 🎯 The Big Picture

Think of this app like WhatsApp or Signal, but focused on calling. Here's the complete architecture:

```
┌─────────────┐         ┌─────────────┐         ┌─────────────┐
│  iPhone A   │ ◄─────► │   Server    │ ◄─────► │  iPhone B   │
│  (Caller)   │ Signaling│             │Signaling│  (Receiver) │
└─────────────┘         └─────────────┘         └─────────────┘
       │                                                │
       └────────────── Direct WebRTC ──────────────────┘
                      (Audio/Video)
```

**Key Concept**: The server only helps phones **find each other** and **exchange connection info**. Once connected, audio/video flows **directly** between phones (peer-to-peer).

---

## 📱 Part 1: First Time Setup - Authentication

### What Happens When You First Open the App

```
User opens app for the first time
    ↓
App checks: "Do I have an auth token in Keychain?"
    ↓
No token found → Show Phone Number Entry Screen
    ↓
User types phone number: +1 555-123-4567
    ↓
User taps "Send Code" button
```

### Behind the Scenes: Sending Verification Code

**File: `Views/Authentication/PhoneNumberEntryView.swift`**

```swift
func sendVerificationCode() async {
    // 1. Validate phone number format
    guard isValidPhoneNumber else { return }

    // 2. Send HTTP POST to your server
    try await AuthenticationService.shared
        .sendVerificationCode(phoneNumber: "+15551234567")
}
```

**File: `Services/Authentication/AuthenticationService.swift`**

```swift
func sendVerificationCode(phoneNumber: String) async throws {
    // POST https://your-api.com/auth/send-code
    // Body: { "phoneNumber": "+15551234567" }

    let body: [String: Any] = ["phoneNumber": phoneNumber]
    let (data, response) = try await URLSession.shared.data(for: request)

    // Server responds: { "success": true }
}
```

### What the Server Does

**Backend: `routes/auth.js`**

```javascript
router.post('/send-code', async (req, res) => {
    const { phoneNumber } = req.body;

    // Use Twilio Verify to send SMS
    const verification = await client.verify.v2
        .services(verifyServiceSid)
        .verifications
        .create({ to: phoneNumber, channel: 'sms' });

    res.json({ success: true });
});
```

**User receives SMS**: "Your verification code is 123456"

### Entering the Verification Code

```
User receives SMS: "Your code is 123456"
    ↓
User enters: 1 2 3 4 5 6
    ↓
App automatically detects 6 digits entered
    ↓
App sends code to server for validation
    ↓
Server validates code with Twilio
    ↓
Server responds with: JWT token + user info
    ↓
App stores token in Keychain (secure storage)
    ↓
User is logged in! → Navigate to Main App
```

### Behind the Scenes: Verifying Code

**File: `Views/Authentication/VerificationCodeView.swift`**

```swift
func verifyCode() async {
    // User entered "123456"

    // Send to server for verification
    let user = try await AuthenticationService.shared
        .verifyCode(code)

    // Server responds with:
    // {
    //   "success": true,
    //   "token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
    //   "user": {
    //     "id": "abc123",
    //     "phoneNumber": "+15551234567"
    //   }
    // }

    // Save token securely in iOS Keychain
    authToken = response.token

    // User is now authenticated!
    appState.login()  // This triggers navigation to main app
}
```

**Backend: Verification**

```javascript
router.post('/verify-code', async (req, res) => {
    const { phoneNumber, code } = req.body;

    // Verify with Twilio
    const check = await client.verify.v2
        .services(verifyServiceSid)
        .verificationChecks
        .create({ to: phoneNumber, code: code });

    if (check.status === 'approved') {
        // Create or get user from database
        const user = await findOrCreateUser(phoneNumber);

        // Generate JWT token (valid for 30 days)
        const token = jwt.sign(
            { userId: user.id, phoneNumber: user.phoneNumber },
            JWT_SECRET,
            { expiresIn: '30d' }
        );

        res.json({ success: true, token, user });
    }
});
```

### Token Storage Security

**File: `Utilities/KeychainHelper.swift`**

```swift
// Tokens are stored in iOS Keychain, NOT UserDefaults
// Keychain is encrypted and survives app uninstalls

static func save(key: String, data: String) {
    let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrAccount as String: key,
        kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        kSecValueData as String: data.data(using: .utf8)!
    ]

    SecItemDelete(query as CFDictionary)  // Remove old
    SecItemAdd(query as CFDictionary, nil) // Add new
}
```

**Why Keychain?**
- Encrypted by iOS
- Survives app deletion (if using sync)
- Can't be accessed by other apps
- Protected by device passcode/biometrics

---

## 📞 Part 2: Making a Call

### Step 1: User Initiates Call

```
User opens Keypad tab
    ↓
User dials: 555-987-6543
    ↓
User taps green phone button 📞
```

**File: `Views/Main/KeypadView.swift`**

```swift
Button(action: {
    // 1. Generate unique ID for this call
    let callId = UUID()

    // 2. Tell CallKit to initiate outgoing call
    CallKitManager.shared.startCall(
        phoneNumber: "+15559876543",
        isVideo: false  // voice call (true for video)
    ) { success in
        if success {
            // CallKit will handle the rest
        }
    }
})
```

### Step 2: CallKit Shows Native iOS Call Screen

**File: `Services/CallKit/CallKitManager.swift`**

```swift
func startCall(phoneNumber: String, isVideo: Bool) {
    let uuid = UUID()
    let handle = CXHandle(type: .phoneNumber, value: phoneNumber)

    // Create call action
    let startAction = CXStartCallAction(call: uuid, handle: handle)
    startAction.isVideo = isVideo

    // Request CallKit to start the call
    callController.request(CXTransaction(action: startAction)) { error in
        if error == nil {
            // CallKit will call our delegate methods
        }
    }
}
```

**What the user sees:**

```
┌─────────────────────────────────┐
│                                 │
│         👤                      │
│      Jane Smith                 │
│   +1 555-987-6543               │
│                                 │
│    Calling...                   │
│                                 │
│                                 │
│      🔇        📢               │
│     Mute     Speaker            │
│                                 │
│          ⭕                     │
│         End                     │
└─────────────────────────────────┘
```

This is the **native iOS call screen** - identical to regular phone calls!

### Step 3: Setting Up WebRTC Connection

**CallKit notifies us via delegate:**

```swift
// File: Services/CallKit/CallKitManager.swift
func provider(_ provider: CXProvider, perform action: CXStartCallAction) {
    // iOS says: "User started a call, now actually connect it"

    // 1. Configure audio session for call
    configureAudioSession()

    // 2. Set up WebRTC peer connection
    webRTCClient.setupPeerConnection()

    // 3. Start capturing local audio (and video if video call)
    webRTCClient.startLocalMedia(isVideoCall: call.isVideo)

    // 4. Tell signaling server to notify the other person
    signalingClient.initiateCall(
        to: call.phoneNumber,
        callId: call.id.uuidString,
        hasVideo: call.isVideo
    )

    // 5. Fulfill the action to tell CallKit we're working on it
    action.fulfill()
}
```

### Step 4: WebRTC Setup Details

**File: `Services/WebRTC/WebRTCClient.swift`**

```swift
func setupPeerConnection() {
    // 1. Configure ICE servers (STUN/TURN)
    let config = RTCConfiguration()
    config.iceServers = [
        RTCIceServer(urlStrings: ["stun:stun.l.google.com:19302"]),
        RTCIceServer(
            urlStrings: ["turn:your-turn-server.com:3478"],
            username: "username",
            credential: "password"
        )
    ]

    // 2. Create peer connection
    peerConnection = factory.peerConnection(
        with: config,
        constraints: constraints,
        delegate: self  // We'll get callbacks
    )
}

func startLocalMedia(isVideoCall: Bool) {
    // 1. Create audio track
    let audioTrack = createAudioTrack()
    peerConnection.add(audioTrack, streamIds: ["stream0"])

    // 2. If video call, create video track
    if isVideoCall {
        let videoTrack = createVideoTrack()
        peerConnection.add(videoTrack, streamIds: ["stream0"])
    }
}
```

### Step 5: Signaling - Notifying the Receiver

**File: `Services/Signaling/SignalingClient.swift`**

```swift
func initiateCall(to: String, callId: String, hasVideo: Bool) {
    // Send message via WebSocket to signaling server
    socket.emit("call-initiate", [
        "to": to,                    // "+15559876543"
        "callId": callId,            // "abc-123-def"
        "hasVideo": hasVideo,        // false
        "from": myPhoneNumber        // "+15551234567"
    ])
}
```

### Step 6: What the Signaling Server Does

**Backend: `signaling-server.js`**

```javascript
socket.on('call-initiate', async (data) => {
    // Received from John:
    // {
    //   to: "+15559876543",
    //   callId: "abc-123",
    //   hasVideo: false,
    //   from: "+15551234567"
    // }

    console.log(`Call from ${data.from} to ${data.to}`);

    // 1. Check if recipient (Jane) is currently online
    const recipientSocket = connectedUsers.get(data.to);

    if (recipientSocket) {
        // Jane is online - send via WebSocket (instant)
        io.to(recipientSocket.socketId).emit('incoming-call', {
            callId: data.callId,
            from: data.from,
            hasVideo: data.hasVideo
        });

        console.log(`Sent WebSocket to ${data.to} (online)`);
    } else {
        // Jane is offline - send VoIP push notification
        const device = await db.devices.findOne({
            phoneNumber: data.to
        });

        if (device && device.voipToken) {
            await sendVoIPPush(device.voipToken, {
                callId: data.callId,
                caller: data.from,
                hasVideo: data.hasVideo
            });

            console.log(`Sent VoIP push to ${data.to} (offline)`);
        } else {
            // Can't reach user
            socket.emit('error', {
                code: 'USER_UNAVAILABLE',
                message: 'User not available'
            });
        }
    }
});
```

---

## 📲 Part 3: Receiving a Call

### Scenario A: App is Running (Foreground or Background)

```
Jane's phone: App is open or in background
    ↓
WebSocket receives "incoming-call" message
    ↓
App processes the message
    ↓
App tells CallKit: "Incoming call from +15551234567"
    ↓
Native iOS incoming call screen appears instantly
```

**File: `Services/Signaling/SignalingClient.swift`**

```swift
// Setup handler for incoming calls
socket.on("incoming-call") { data, ack in
    guard let dict = data.first as? [String: Any],
          let callId = dict["callId"] as? String,
          let from = dict["from"] as? String,
          let hasVideo = dict["hasVideo"] as? Bool else { return }

    // Notify delegate (usually CallKit manager)
    delegate?.signalingClient(
        self,
        didReceiveIncomingCall: callId,
        from: from,
        hasVideo: hasVideo
    )
}
```

### Scenario B: App is Completely Closed (The Magic!)

This is where **VoIP Push Notifications** shine:

```
Jane's phone: App is COMPLETELY TERMINATED
    ↓
Apple Push Notification Service (APNs) receives push from server
    ↓
APNs delivers VoIP push to Jane's device
    ↓
iOS WAKES UP THE APP IN THE BACKGROUND (even if force-quit!)
    ↓
App has ~10 seconds to process the push
    ↓
App tells CallKit: "Incoming call"
    ↓
CallKit shows incoming call on LOCK SCREEN
```

**File: `Services/VoIP/VoIPPushManager.swift`**

```swift
func pushRegistry(_ registry: PKPushRegistry,
                 didReceiveIncomingPushWith payload: PKPushPayload,
                 for type: PKPushType,
                 completion: @escaping () -> Void) {

    // iOS just woke us up with a VoIP push!
    print("=== VoIP Push Received ===")
    print("Payload: \(payload.dictionaryPayload)")

    // Extract call information from push
    guard let callIdString = payload.dictionaryPayload["callId"] as? String,
          let callId = UUID(uuidString: callIdString),
          let caller = payload.dictionaryPayload["caller"] as? String,
          let hasVideo = payload.dictionaryPayload["hasVideo"] as? Bool
    else {
        print("Invalid VoIP payload")
        completion()
        return
    }

    // THIS IS CRITICAL: You MUST report to CallKit
    // If you don't, Apple will reject your app
    CallKitManager.shared.reportIncomingCall(
        uuid: callId,
        phoneNumber: caller,
        hasVideo: hasVideo
    ) { error in
        if let error = error {
            print("Error reporting call: \(error)")
        }

        // Always call completion handler
        completion()
    }
}
```

### What Jane Sees on Her Lock Screen

```
🔒 Lock Screen

┌─────────────────────────────────┐
│  iPhone Call                    │
│                                 │
│         👤                      │
│      John Doe                   │
│   +1 555-123-4567               │
│                                 │
│  🔕            ⏰              │
│ Remind Me    Message            │
│                                 │
│   ⭕              ✅            │
│ Decline          Accept         │
└─────────────────────────────────┘
```

**This appears even if:**
- Phone is locked
- App was force-quit
- Phone is in Do Not Disturb (depends on settings)
- Phone hasn't been unlocked in days

### Reporting to CallKit

**File: `Services/CallKit/CallKitManager.swift`**

```swift
func reportIncomingCall(uuid: UUID,
                       phoneNumber: String,
                       hasVideo: Bool,
                       completion: @escaping (Error?) -> Void) {

    // Create call update with caller info
    let update = CXCallUpdate()
    update.remoteHandle = CXHandle(type: .phoneNumber, value: phoneNumber)
    update.hasVideo = hasVideo

    // Try to get contact name
    if let contactName = ContactsManager.shared.getContactName(for: phoneNumber) {
        update.localizedCallerName = contactName  // Shows "John Doe"
    } else {
        update.localizedCallerName = phoneNumber   // Shows "+15551234567"
    }

    // Report to CallKit
    provider.reportNewIncomingCall(with: uuid, update: update) { error in
        if error == nil {
            // Success! CallKit is showing incoming call UI
            let call = Call(
                id: uuid,
                phoneNumber: phoneNumber,
                isVideo: hasVideo,
                isOutgoing: false
            )
            self.addCall(call)
        }

        completion(error)
    }
}
```

---

## 🤝 Part 4: Connecting the Call (WebRTC Handshake)

When Jane taps "Accept", both phones need to exchange information to establish a direct connection.

### Step 1: Jane Accepts the Call

```swift
// File: Services/CallKit/CallKitManager.swift
func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
    // Jane tapped "Accept"

    // 1. Configure audio session
    configureAudioSession()

    // 2. Get the call
    guard let call = findCall(uuid: action.callUUID) else {
        action.fail()
        return
    }

    // 3. Setup WebRTC
    webRTCClient.setupPeerConnection()
    webRTCClient.startLocalMedia(isVideoCall: call.isVideo)

    // 4. Tell signaling server Jane accepted
    signalingClient.acceptCall(callId: call.id.uuidString)

    // 5. Tell CallKit we fulfilled the action
    action.fulfill()
}
```

### Step 2: Exchange Session Descriptions (SDP)

**SDP = Session Description Protocol**
Describes each phone's media capabilities (codecs, formats, network info)

#### John's Phone Creates an Offer

```swift
// File: Services/WebRTC/WebRTCClient.swift
func makeOffer(completion: @escaping (String) -> Void) {
    let constraints = RTCMediaConstraints(
        mandatoryConstraints: [
            "OfferToReceiveAudio": "true",
            "OfferToReceiveVideo": call.isVideo ? "true" : "false"
        ],
        optionalConstraints: nil
    )

    peerConnection.offer(for: constraints) { sdp, error in
        guard let sdp = sdp, error == nil else { return }

        // Set this as our local description
        self.peerConnection.setLocalDescription(sdp) { error in
            if error == nil {
                // Convert SDP to JSON string
                let offer = sdp.sdp  // This is a long string like:
                // "v=0
                //  o=- 123456789 2 IN IP4 127.0.0.1
                //  s=-
                //  t=0 0
                //  a=group:BUNDLE 0 1
                //  m=audio 9 UDP/TLS/RTP/SAVPF 111 103 104
                //  a=rtpmap:111 opus/48000/2
                //  ..."

                completion(offer)
            }
        }
    }
}
```

#### Send Offer to Jane

```swift
// File: Services/Signaling/SignalingClient.swift
func sendOffer(_ sdp: String, forCall callId: String) {
    socket.emit("offer", [
        "callId": callId,
        "sdp": sdp
    ])
}
```

#### Server Forwards to Jane

```javascript
// Backend
socket.on('offer', (data) => {
    const { callId, sdp } = data;

    // Find the other person in this call
    const call = activeCalls.get(callId);
    const recipient = call.callee;  // Jane
    const recipientSocket = connectedUsers.get(recipient);

    // Forward offer to Jane
    io.to(recipientSocket.socketId).emit('offer', {
        callId,
        sdp
    });
});
```

#### Jane Receives Offer and Creates Answer

```swift
// File: Services/Signaling/SignalingClient.swift
socket.on("offer") { data, ack in
    guard let dict = data.first as? [String: Any],
          let callId = dict["callId"] as? String,
          let sdpString = dict["sdp"] as? String else { return }

    // Create SDP object from string
    let sdp = RTCSessionDescription(type: .offer, sdp: sdpString)

    // Set as remote description
    webRTCClient.handleRemoteDescription(sdp)

    // Now create our answer
    webRTCClient.makeAnswer { answer in
        signalingClient.sendAnswer(answer, forCall: callId)
    }
}
```

#### Server Forwards Answer Back to John

```javascript
socket.on('answer', (data) => {
    const { callId, sdp } = data;

    const call = activeCalls.get(callId);
    const recipient = call.caller;  // John
    const recipientSocket = connectedUsers.get(recipient);

    io.to(recipientSocket.socketId).emit('answer', {
        callId,
        sdp
    });
});
```

#### John Receives Answer

```swift
socket.on("answer") { data, ack in
    guard let dict = data.first as? [String: Any],
          let sdpString = dict["sdp"] as? String else { return }

    let sdp = RTCSessionDescription(type: .answer, sdp: sdpString)
    webRTCClient.handleRemoteDescription(sdp)

    // Now both phones know each other's capabilities!
}
```

### Step 3: Exchange ICE Candidates (Network Addresses)

**ICE = Interactive Connectivity Establishment**
Each phone discovers all possible network paths to reach it.

#### Discovering Network Addresses

```
John's Phone discovers:
├── 192.168.1.5:54321 (Local WiFi - if on same network)
├── 10.0.0.5:12345 (VPN address - if VPN is on)
└── 98.76.54.32:54321 (Public IP - via STUN server)

Jane's Phone discovers:
├── 192.168.50.10:43210 (Local WiFi)
├── 172.16.0.5:23456 (Cellular data)
└── 123.45.67.89:43210 (Public IP - via STUN server)
```

#### How Candidates are Discovered and Sent

```swift
// File: Services/WebRTC/WebRTCClient.swift
extension WebRTCClient: RTCPeerConnectionDelegate {

    func peerConnection(_ pc: RTCPeerConnection,
                       didGenerate candidate: RTCIceCandidate) {
        // WebRTC discovered a network path!

        print("ICE Candidate found:")
        print("  IP: \(candidate.sdp)")  // "candidate:1 1 UDP 2130706431 192.168.1.5 54321 typ host"
        print("  Type: host/srflx/relay")

        // Convert to dictionary
        let candidateDict: [String: Any] = [
            "candidate": candidate.sdp,
            "sdpMLineIndex": candidate.sdpMLineIndex,
            "sdpMid": candidate.sdpMid ?? ""
        ]

        // Send to other phone via signaling
        signalingClient.sendIceCandidate(candidateDict, forCall: callId)
    }
}
```

#### Server Forwards Candidates

```javascript
socket.on('ice-candidate', (data) => {
    const { callId, candidate } = data;

    // Find other person
    const call = activeCalls.get(callId);
    const isFromCaller = socket.phoneNumber === call.caller;
    const recipient = isFromCaller ? call.callee : call.caller;
    const recipientSocket = connectedUsers.get(recipient);

    // Forward candidate
    if (recipientSocket) {
        io.to(recipientSocket.socketId).emit('ice-candidate', {
            callId,
            candidate
        });
    }
});
```

#### Receiving and Adding Candidates

```swift
socket.on("ice-candidate") { data, ack in
    guard let dict = data.first as? [String: Any],
          let candidateDict = dict["candidate"] as? [String: Any],
          let sdp = candidateDict["candidate"] as? String,
          let sdpMLineIndex = candidateDict["sdpMLineIndex"] as? Int32,
          let sdpMid = candidateDict["sdpMid"] as? String else { return }

    // Create ICE candidate object
    let candidate = RTCIceCandidate(
        sdp: sdp,
        sdpMLineIndex: sdpMLineIndex,
        sdpMid: sdpMid
    )

    // Add to peer connection
    peerConnection.add(candidate) { error in
        if error == nil {
            print("ICE candidate added successfully")
        }
    }
}
```

### Step 4: Connection Establishment

WebRTC now tries all possible paths:

```
Trying connection paths (in order of preference):

1. Direct WiFi → WiFi (host-to-host)
   ✅ If both on same network: FASTEST (0-10ms latency)
   ❌ If on different networks: Can't connect

2. Direct via Public IPs (srflx)
   ✅ If no firewall blocking: FAST (20-50ms latency)
   ❌ If NAT/firewall: Can't connect

3. Via TURN Relay Server (relay)
   ✅ Always works: RELIABLE (50-150ms latency)
   💰 Uses server bandwidth: COSTS MONEY
```

#### When Connection Succeeds

```swift
func peerConnection(_ pc: RTCPeerConnection,
                   didChange state: RTCIceConnectionState) {

    switch state {
    case .checking:
        print("Checking connection paths...")

    case .connected:
        print("🎉 Connected! Audio/video is now flowing!")

        // Tell CallKit the call is connected
        provider.reportOutgoingCall(
            with: callId,
            connectedAt: Date()
        )

        // Update UI
        callState = .connected

    case .completed:
        print("Connection fully established and verified")

    case .failed:
        print("❌ Connection failed")
        // End call, show error to user

    case .disconnected:
        print("⚠️ Temporarily disconnected, trying to reconnect...")

    case .closed:
        print("Connection closed")

    @unknown default:
        break
    }
}
```

---

## 🎙️ Part 5: During the Call - Media Flow

### Audio Streaming (Encrypted End-to-End)

```
John's Side:
┌─────────────────────────────────────────────┐
│ 1. Microphone captures audio                │
│    ↓                                         │
│ 2. AVFoundation provides raw audio samples  │
│    ↓                                         │
│ 3. WebRTC encodes to Opus codec             │
│    (Compresses: 64 kbps for voice)          │
│    ↓                                         │
│ 4. Encrypts with DTLS-SRTP                  │
│    (AES-128, unique keys per call)          │
│    ↓                                         │
│ 5. Splits into RTP packets (~20ms each)     │
│    ↓                                         │
│ 6. Sends over UDP (direct or via TURN)      │
└─────────────────────────────────────────────┘
                    │
                    │ Internet
                    │ (Encrypted packets)
                    ▼
┌─────────────────────────────────────────────┐
│ Jane's Side:                                 │
│                                              │
│ 1. Receives RTP packets over UDP            │
│    ↓                                         │
│ 2. Decrypts with DTLS-SRTP                  │
│    ↓                                         │
│ 3. Decodes from Opus to raw audio           │
│    ↓                                         │
│ 4. Buffers to handle jitter                 │
│    ↓                                         │
│ 5. AVFoundation plays through speaker       │
│    ↓                                         │
│ 6. User hears John's voice                  │
└─────────────────────────────────────────────┘
```

**Key Points:**
- All happens automatically by WebRTC
- ~30-100ms total latency (network dependent)
- Server NEVER sees decrypted audio
- Adapts quality based on network conditions

### Call Controls Implementation

#### Mute Button

```swift
// File: Views/Call/ActiveCallView.swift
func toggleMute() {
    isMuted.toggle()

    // 1. Mute local audio track
    webRTCClient.muteAudio(isMuted)

    // 2. Update CallKit
    let muteAction = CXSetMutedCallAction(
        call: currentCallId,
        muted: isMuted
    )
    callController.request(CXTransaction(action: muteAction))
}
```

```swift
// File: Services/WebRTC/WebRTCClient.swift
func muteAudio(_ mute: Bool) {
    localAudioTrack?.isEnabled = !mute

    // When muted: microphone still captures, but doesn't send
    // Other person hears silence
}
```

#### Speaker Button

```swift
func toggleSpeaker() {
    isSpeaker.toggle()

    let audioSession = AVAudioSession.sharedInstance()

    do {
        if isSpeaker {
            // Route to loud speaker
            try audioSession.overrideOutputAudioPort(.speaker)
        } else {
            // Route to earpiece
            try audioSession.overrideOutputAudioPort(.none)
        }
    } catch {
        print("Error toggling speaker: \(error)")
    }
}
```

#### Call Timer

```swift
// File: Views/Call/ActiveCallView.swift
struct ActiveCallView: View {
    @State private var callDuration: TimeInterval = 0

    var body: some View {
        Text(formatDuration(callDuration))
            .font(.title2)
            .onAppear {
                startTimer()
            }
    }

    func startTimer() {
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            callDuration += 1
        }
    }

    func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
```

---

## 📹 Part 6: Video Calls

### Capturing Video

```swift
// File: Services/WebRTC/WebRTCClient.swift
func createVideoTrack() -> RTCVideoTrack {
    // 1. Create video source
    let videoSource = factory.videoSource()

    // 2. Create camera capturer
    let videoCapturer = RTCCameraVideoCapturer(delegate: videoSource)
    self.videoCapturer = videoCapturer

    // 3. Get front camera
    guard let frontCamera = RTCCameraVideoCapturer.captureDevices()
        .first(where: { $0.position == .front }) else {
        fatalError("No front camera")
    }

    // 4. Get best format (prefer 640x480 or higher)
    let formats = RTCCameraVideoCapturer.supportedFormats(for: frontCamera)
    let format = formats.last  // Usually highest resolution

    // 5. Get max frame rate (usually 30fps)
    let fps = format?.videoSupportedFrameRateRanges
        .max { $0.maxFrameRate < $1.maxFrameRate }?
        .maxFrameRate ?? 30

    // 6. Start capturing
    videoCapturer.startCapture(
        with: frontCamera,
        format: format!,
        fps: Int(fps)
    )

    // 7. Create video track
    return factory.videoTrack(with: videoSource, trackId: "video0")
}
```

### Rendering Video

#### Local Video (Your Camera)

```swift
// File: Views/Call/VideoCallView.swift
struct LocalVideoView: UIViewRepresentable {
    let videoTrack: RTCVideoTrack

    func makeUIView(context: Context) -> RTCMTLVideoView {
        let videoView = RTCMTLVideoView()
        videoView.contentMode = .scaleAspectFill
        return videoView
    }

    func updateUIView(_ videoView: RTCMTLVideoView, context: Context) {
        videoTrack.add(videoView)
    }
}
```

#### Remote Video (Other Person)

```swift
// When remote video arrives
func peerConnection(_ pc: RTCPeerConnection,
                   didAdd stream: RTCMediaStream) {

    if let videoTrack = stream.videoTracks.first {
        print("Received remote video track")

        // Add to video view
        DispatchQueue.main.async {
            self.remoteVideoTrack = videoTrack
            self.delegate?.webRTCClient(self, didReceiveRemoteVideoTrack: videoTrack)
        }
    }
}
```

### Video Call UI

```swift
struct VideoCallView: View {
    let localVideoTrack: RTCVideoTrack
    let remoteVideoTrack: RTCVideoTrack?

    @State private var showControls = true

    var body: some View {
        ZStack {
            // Remote video (full screen)
            if let remoteTrack = remoteVideoTrack {
                RemoteVideoView(videoTrack: remoteTrack)
                    .edgesIgnoringSafeArea(.all)
            } else {
                Color.black
                    .edgesIgnoringSafeArea(.all)

                Text("Connecting...")
                    .foregroundColor(.white)
            }

            // Local video (picture-in-picture)
            VStack {
                HStack {
                    Spacer()
                    LocalVideoView(videoTrack: localVideoTrack)
                        .frame(width: 120, height: 160)
                        .cornerRadius(12)
                        .padding()
                }
                Spacer()
            }

            // Controls (overlay)
            if showControls {
                VStack {
                    Spacer()

                    HStack(spacing: 40) {
                        Button(action: toggleMute) {
                            Image(systemName: isMuted ? "mic.slash.fill" : "mic.fill")
                                .font(.title)
                        }

                        Button(action: toggleVideo) {
                            Image(systemName: isVideoOff ? "video.slash.fill" : "video.fill")
                                .font(.title)
                        }

                        Button(action: flipCamera) {
                            Image(systemName: "arrow.triangle.2.circlepath.camera.fill")
                                .font(.title)
                        }

                        Button(action: endCall) {
                            Image(systemName: "phone.down.fill")
                                .font(.title)
                                .foregroundColor(.white)
                                .frame(width: 70, height: 70)
                                .background(Color.red)
                                .clipShape(Circle())
                        }
                    }
                    .foregroundColor(.white)
                    .padding(.bottom, 40)
                }
            }
        }
        .onTapGesture {
            withAnimation {
                showControls.toggle()
            }

            // Auto-hide after 3 seconds
            if showControls {
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    withAnimation {
                        showControls = false
                    }
                }
            }
        }
    }
}
```

### Switching Cameras

```swift
func flipCamera() {
    guard let capturer = videoCapturer else { return }

    // Get current camera
    let currentPosition = currentCameraPosition

    // Find opposite camera
    let newPosition: AVCaptureDevice.Position =
        currentPosition == .front ? .back : .front

    guard let newCamera = RTCCameraVideoCapturer.captureDevices()
        .first(where: { $0.position == newPosition }) else { return }

    // Get format and fps
    let formats = RTCCameraVideoCapturer.supportedFormats(for: newCamera)
    let format = formats.last
    let fps = 30

    // Switch camera
    capturer.startCapture(
        with: newCamera,
        format: format!,
        fps: fps
    )

    currentCameraPosition = newPosition
}
```

---

## 🔚 Part 7: Ending the Call

### User Taps End Button

```
John taps red "End Call" button
    ↓
App tells CallKit to end call
    ↓
CallKit calls our delegate method
    ↓
We close WebRTC connection
    ↓
We notify signaling server
    ↓
Server tells Jane "call ended"
    ↓
Both phones clean up
    ↓
Call added to Recents history
```

### Implementation

```swift
// File: Views/Call/ActiveCallView.swift
Button(action: {
    // User tapped end button
    CallKitManager.shared.endCall(uuid: currentCallId)
})
```

```swift
// File: Services/CallKit/CallKitManager.swift
func endCall(uuid: UUID) {
    let endAction = CXEndCallAction(call: uuid)
    let transaction = CXTransaction(action: endAction)

    callController.request(transaction) { error in
        if error == nil {
            // CallKit will call our delegate
        }
    }
}

func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
    // CallKit says: "End this call"

    guard let call = findCall(uuid: action.callUUID) else {
        action.fail()
        return
    }

    // 1. Close WebRTC connection
    webRTCClient.close()

    // 2. Notify signaling server
    signalingClient.endCall(callId: call.id.uuidString)

    // 3. Save to call history
    saveToCallHistory(call)

    // 4. Remove from active calls
    removeCall(call)

    // 5. Tell CallKit we're done
    action.fulfill()
}
```

```swift
// File: Services/WebRTC/WebRTCClient.swift
func close() {
    // Stop capturing
    videoCapturer?.stopCapture()

    // Remove tracks
    localAudioTrack = nil
    localVideoTrack = nil

    // Close peer connection
    peerConnection?.close()
    peerConnection = nil

    print("WebRTC connection closed")
}
```

### Server Cleanup

```javascript
socket.on('call-end', (data) => {
    const { callId } = data;
    const call = activeCalls.get(callId);

    if (!call) return;

    // Notify other person
    const otherPerson = socket.phoneNumber === call.caller
        ? call.callee
        : call.caller;

    const otherSocket = connectedUsers.get(otherPerson);
    if (otherSocket) {
        io.to(otherSocket.socketId).emit('call-ended', { callId });
    }

    // Remove call from active calls
    activeCalls.delete(callId);

    console.log(`Call ${callId} ended`);
});
```

---

## 🔐 Security & Encryption

### Layer 1: Transport Security (HTTPS/WSS)

```
Client ←→ Server Communication:
├── REST API: HTTPS (TLS 1.3)
│   └── Encrypts: Login, verification codes, user data
│
└── Signaling: WSS (WebSocket Secure)
    └── Encrypts: Call setup messages, SDP, ICE candidates
```

### Layer 2: Media Encryption (DTLS-SRTP)

```
Caller ←→ Receiver Media:
└── DTLS-SRTP (Datagram TLS + Secure RTP)
    ├── Encryption: AES-128-GCM
    ├── Key Exchange: DTLS handshake (like HTTPS but for UDP)
    └── Keys: Unique per call, never reused

Result: Server CANNOT decrypt audio/video
```

### Layer 3: Token Security

```swift
// Tokens stored in iOS Keychain
// - Hardware encrypted
// - Requires device unlock
// - Inaccessible to other apps
// - Survives app deletion (with iCloud Keychain)

KeychainHelper.save(key: "authToken", data: token)
```

### Security Verification

```swift
func verifyEncryption() {
    peerConnection.statistics { report in
        for (_, stats) in report.statistics {
            if stats.type == "transport" {
                // Check DTLS state
                if let dtlsState = stats.values["dtlsState"] as? String {
                    print("DTLS State: \(dtlsState)")
                    // Should be "connected"
                }

                // Check encryption cipher
                if let srtpCipher = stats.values["srtpCipher"] as? String {
                    print("SRTP Cipher: \(srtpCipher)")
                    // Should be "AES_CM_128_HMAC_SHA1_80" or better
                }
            }
        }
    }
}
```

---

## 📊 Complete End-to-End Flow

```
┌────────────────────────────────────────────────────────────────────┐
│ STEP 1: AUTHENTICATION                                             │
├────────────────────────────────────────────────────────────────────┤
│ User enters phone → Server sends SMS → User enters code →         │
│ Server validates → Returns JWT token → Stored in Keychain         │
└────────────────────────────────────────────────────────────────────┘
                              ↓
┌────────────────────────────────────────────────────────────────────┐
│ STEP 2: APP STARTUP (Next time)                                    │
├────────────────────────────────────────────────────────────────────┤
│ App loads → Checks Keychain → Token found → Connect WebSocket →   │
│ Register for VoIP pushes → Ready to receive calls                 │
└────────────────────────────────────────────────────────────────────┘
                              ↓
┌────────────────────────────────────────────────────────────────────┐
│ STEP 3: MAKING A CALL (John)                                       │
├────────────────────────────────────────────────────────────────────┤
│ Dial number → Tap call → CallKit shows UI → Setup WebRTC →        │
│ Send "call-initiate" to server → Server sends to Jane             │
└────────────────────────────────────────────────────────────────────┘
                              ↓
┌────────────────────────────────────────────────────────────────────┐
│ STEP 4: RECEIVING CALL (Jane)                                      │
├────────────────────────────────────────────────────────────────────┤
│ VoIP push wakes app → Report to CallKit → Lock screen shows call →│
│ Jane taps Accept → Setup WebRTC → Send "call-accept"              │
└────────────────────────────────────────────────────────────────────┘
                              ↓
┌────────────────────────────────────────────────────────────────────┐
│ STEP 5: CONNECTING (WebRTC Handshake)                              │
├────────────────────────────────────────────────────────────────────┤
│ John creates offer → Send via server → Jane receives →            │
│ Jane creates answer → Send via server → John receives →           │
│ Both exchange ICE candidates → Try connection paths →             │
│ Connected! (direct or via TURN)                                    │
└────────────────────────────────────────────────────────────────────┘
                              ↓
┌────────────────────────────────────────────────────────────────────┐
│ STEP 6: ACTIVE CALL                                                │
├────────────────────────────────────────────────────────────────────┤
│ Audio flows John ↔ Jane (encrypted, peer-to-peer)                 │
│ User can: Mute, Speaker, End call                                 │
│ Video call: Camera video also flows                               │
└────────────────────────────────────────────────────────────────────┘
                              ↓
┌────────────────────────────────────────────────────────────────────┐
│ STEP 7: ENDING CALL                                                │
├────────────────────────────────────────────────────────────────────┤
│ Either user taps End → Close WebRTC → Notify server →             │
│ Server tells other person → Both clean up → Save to history       │
└────────────────────────────────────────────────────────────────────┘
```

---

## 🎯 Key Components Summary

| Component | Purpose | Technology |
|-----------|---------|------------|
| **CallKit** | Native iOS call screens and integration | Apple Framework |
| **WebRTC** | Peer-to-peer audio/video | GoogleWebRTC (C++) |
| **Signaling Server** | Help phones find each other | Node.js + Socket.io |
| **VoIP Push** | Wake app for incoming calls | Apple PushKit |
| **Authentication** | Phone number login | Twilio Verify / Custom |
| **STUN Server** | Discover public IP | Google STUN / Custom |
| **TURN Server** | Relay when direct fails | coturn |
| **Database** | Store users, device tokens | PostgreSQL |

---

## 💡 Why This Architecture?

### CallKit
- Users expect native iOS call experience
- Lock screen integration essential
- System integration (Bluetooth, CarPlay)
- Accessibility features built-in

### WebRTC
- Industry standard (used by Zoom, Google Meet, Discord)
- Built-in encryption (DTLS-SRTP)
- Peer-to-peer = low latency
- Handles NAT traversal automatically
- Adaptive bitrate based on network

### VoIP Push
- Only way to receive calls when app terminated
- System-level priority (guaranteed delivery)
- Low latency (<2 seconds typically)
- No user notification required

### Phone Number Auth
- Familiar to users (no passwords to remember)
- Prevents spam (SMS verification costs money)
- Unique identifier globally
- Can sync contacts easily

### Signaling Server
- Lightweight (only for setup, not media)
- Can be simple Node.js app
- Scales horizontally easily
- Open source friendly

---

## 📈 Scalability Considerations

### 1000 Users

```
Signaling Server:
├── Single Node.js instance: ✅ Handles easily
├── RAM: ~500MB
├── CPU: <10%
└── Database: PostgreSQL on same server

TURN Server:
├── May not need (most calls direct)
└── If needed: t2.small instance
```

### 10,000 Users

```
Signaling Server:
├── 2-3 Node.js instances (load balanced)
├── Redis for session sharing
├── Database: Dedicated RDS instance
└── Monitoring: Datadog/New Relic

TURN Server:
├── Definitely needed (~30% of calls)
├── Multiple instances in different regions
└── ~500 Mbps bandwidth per 100 concurrent calls
```

### 100,000+ Users

```
Signaling Server:
├── Auto-scaling group (5-20 instances)
├── Redis Cluster for sessions
├── Database: RDS with read replicas
├── CDN for static assets
└── Full monitoring and alerting

TURN Server:
├── Regional TURN servers (US East, West, EU, Asia)
├── Load balancing across TURN servers
├── ~5 Gbps bandwidth capacity
└── Or use managed service (Twilio, Xirsys)
```

---

## 🚀 Performance Characteristics

### Call Setup Time
```
Target: < 3 seconds from tap to ring

Breakdown:
├── CallKit setup: 100-300ms
├── WebRTC init: 200-500ms
├── Signaling roundtrip: 100-500ms (network dependent)
├── VoIP push delivery: 500-2000ms (if app closed)
└── ICE gathering: 500-1500ms
```

### Call Quality
```
Audio:
├── Codec: Opus (best for voice)
├── Bitrate: 24-64 kbps (adaptive)
├── Latency: 30-150ms (network dependent)
└── Packet loss: Handled up to ~5%

Video:
├── Codec: H.264 or VP8
├── Resolution: 640x480 to 1280x720
├── Framerate: 15-30 fps (adaptive)
├── Bitrate: 500 kbps - 2 Mbps
└── Latency: 100-300ms
```

### Battery Impact
```
Audio Call:
└── ~2-3% battery per hour

Video Call:
└── ~8-12% battery per hour
```

---

## 🎓 Learning Resources

Want to dive deeper? Check these out:

- **WebRTC**: https://webrtc.org/getting-started/overview
- **CallKit**: https://developer.apple.com/documentation/callkit
- **Socket.io**: https://socket.io/docs/v4/
- **Opus Codec**: https://opus-codec.org/
- **STUN/TURN**: https://www.html5rocks.com/en/tutorials/webrtc/infrastructure/

---

This is exactly how modern calling apps work! WhatsApp, Signal, Discord, Zoom - they all use variations of this architecture. The magic is in combining these technologies seamlessly to create a great user experience.

**Questions? Want more detail on any specific part?** Let me know! 🚀

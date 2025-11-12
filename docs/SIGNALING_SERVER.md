# Signaling Server Architecture

## Overview

The signaling server facilitates the exchange of connection information between peers before a WebRTC connection can be established. It handles:

- User registration and presence
- Call initiation and termination
- SDP offer/answer exchange
- ICE candidate exchange
- VoIP push notification triggers

## Why Do We Need Signaling?

WebRTC provides peer-to-peer communication, but peers need a way to:
1. Discover each other
2. Exchange connection metadata (SDP)
3. Exchange network information (ICE candidates)
4. Coordinate call setup and teardown

The signaling server provides this coordination layer.

## Technology Choices

### Option 1: Node.js + Socket.io (Recommended)

**Pros:**
- Easy to implement
- Great WebSocket library (Socket.io)
- Large ecosystem
- Good performance
- Built-in room support

**Cons:**
- Single-threaded (can cluster)
- Not as performant as Go for very high scale

**When to use:** Most projects, rapid development

### Option 2: Go + Gorilla WebSocket

**Pros:**
- Excellent performance
- Low memory footprint
- Built-in concurrency
- Compiled binary

**Cons:**
- Steeper learning curve
- Smaller ecosystem than Node.js

**When to use:** High-scale production systems

### Option 3: Python + asyncio

**Pros:**
- Python ecosystem
- async/await support
- Good for ML integration

**Cons:**
- Slower than Node.js and Go
- Less mature WebSocket libraries

**When to use:** When integrating with Python services

## Signaling Protocol

### Message Types

```typescript
// Client -> Server messages
interface RegisterMessage {
    type: 'register';
    phoneNumber: string;
    deviceToken: string;  // APNs device token
    token: string;        // JWT auth token
}

interface CallInitiateMessage {
    type: 'call-initiate';
    to: string;           // Recipient phone number
    callId: string;       // UUID
    hasVideo: boolean;
    from: string;         // Caller phone number
}

interface CallAcceptMessage {
    type: 'call-accept';
    callId: string;
}

interface CallRejectMessage {
    type: 'call-reject';
    callId: string;
    reason?: string;
}

interface CallEndMessage {
    type: 'call-end';
    callId: string;
}

interface OfferMessage {
    type: 'offer';
    callId: string;
    sdp: string;
}

interface AnswerMessage {
    type: 'answer';
    callId: string;
    sdp: string;
}

interface IceCandidateMessage {
    type: 'ice-candidate';
    callId: string;
    candidate: RTCIceCandidateInit;
}

// Server -> Client messages
interface IncomingCallMessage {
    type: 'incoming-call';
    callId: string;
    from: string;
    hasVideo: boolean;
    callerName?: string;
}

interface CallAnsweredMessage {
    type: 'call-answered';
    callId: string;
}

interface CallRejectedMessage {
    type: 'call-rejected';
    callId: string;
    reason?: string;
}

interface CallEndedMessage {
    type: 'call-ended';
    callId: string;
    reason?: string;
}

interface ErrorMessage {
    type: 'error';
    code: string;
    message: string;
}
```

## Node.js Implementation

### Server Setup

```javascript
// server.js
const express = require('express');
const http = require('http');
const { Server } = require('socket.io');
const jwt = require('jsonwebtoken');
const redis = require('redis');
const apn = require('apn');

const app = express();
const server = http.createServer(app);
const io = new Server(server, {
    cors: {
        origin: '*', // Configure properly in production
        methods: ['GET', 'POST']
    }
});

// Redis for session/presence management
const redisClient = redis.createClient({
    url: process.env.REDIS_URL || 'redis://localhost:6379'
});

// APNs for push notifications
const apnProvider = new apn.Provider({
    token: {
        key: './AuthKey.p8',
        keyId: process.env.APN_KEY_ID,
        teamId: process.env.APN_TEAM_ID
    },
    production: process.env.NODE_ENV === 'production'
});

// Connected users: phoneNumber -> socketId
const connectedUsers = new Map();

// Active calls: callId -> { caller, callee, status }
const activeCalls = new Map();

const JWT_SECRET = process.env.JWT_SECRET || 'your-secret-key';

// Middleware: Authenticate WebSocket connection
io.use((socket, next) => {
    const token = socket.handshake.auth.token;

    if (!token) {
        return next(new Error('Authentication required'));
    }

    try {
        const decoded = jwt.verify(token, JWT_SECRET);
        socket.phoneNumber = decoded.phoneNumber;
        socket.userId = decoded.userId;
        next();
    } catch (err) {
        next(new Error('Invalid token'));
    }
});

// Connection handler
io.on('connection', (socket) => {
    console.log(`User connected: ${socket.phoneNumber} (${socket.id})`);

    // Register user
    socket.on('register', async (data) => {
        const { deviceToken } = data;

        // Store connection
        connectedUsers.set(socket.phoneNumber, {
            socketId: socket.id,
            deviceToken,
            connectedAt: Date.now()
        });

        // Store in Redis for multi-server setup
        await redisClient.hSet('users', socket.phoneNumber, JSON.stringify({
            socketId: socket.id,
            deviceToken,
            serverId: process.env.SERVER_ID || 'server-1'
        }));

        socket.emit('registered', { success: true });
    });

    // Call initiation
    socket.on('call-initiate', async (data) => {
        const { to, callId, hasVideo } = data;
        const from = socket.phoneNumber;

        console.log(`Call initiated: ${from} -> ${to} (${callId})`);

        // Check if recipient is registered
        const recipient = connectedUsers.get(to);

        // Store call
        activeCalls.set(callId, {
            caller: from,
            callee: to,
            hasVideo,
            status: 'ringing',
            initiatedAt: Date.now()
        });

        if (recipient) {
            // Recipient is online - send via WebSocket
            io.to(recipient.socketId).emit('incoming-call', {
                callId,
                from,
                hasVideo,
                callerName: data.callerName
            });
        } else {
            // Recipient is offline - send push notification
            const recipientData = await redisClient.hGet('users', to);

            if (recipientData) {
                const { deviceToken } = JSON.parse(recipientData);
                await sendVoIPPush(deviceToken, {
                    callId,
                    caller: from,
                    hasVideo
                });
            } else {
                socket.emit('error', {
                    code: 'USER_NOT_FOUND',
                    message: 'Recipient not found'
                });
                activeCalls.delete(callId);
            }
        }
    });

    // Call acceptance
    socket.on('call-accept', (data) => {
        const { callId } = data;
        const call = activeCalls.get(callId);

        if (!call) {
            socket.emit('error', { code: 'CALL_NOT_FOUND', message: 'Call not found' });
            return;
        }

        call.status = 'accepted';

        // Notify caller
        const caller = connectedUsers.get(call.caller);
        if (caller) {
            io.to(caller.socketId).emit('call-answered', { callId });
        }
    });

    // Call rejection
    socket.on('call-reject', (data) => {
        const { callId, reason } = data;
        const call = activeCalls.get(callId);

        if (!call) return;

        call.status = 'rejected';

        // Notify caller
        const caller = connectedUsers.get(call.caller);
        if (caller) {
            io.to(caller.socketId).emit('call-rejected', { callId, reason });
        }

        // Clean up
        activeCalls.delete(callId);
    });

    // Call end
    socket.on('call-end', (data) => {
        const { callId } = data;
        const call = activeCalls.get(callId);

        if (!call) return;

        // Notify other party
        const otherParty = socket.phoneNumber === call.caller ? call.callee : call.caller;
        const otherUser = connectedUsers.get(otherParty);

        if (otherUser) {
            io.to(otherUser.socketId).emit('call-ended', { callId });
        }

        // Clean up
        activeCalls.delete(callId);
    });

    // SDP Offer
    socket.on('offer', (data) => {
        const { callId, sdp } = data;
        const call = activeCalls.get(callId);

        if (!call) return;

        // Forward to callee
        const recipient = socket.phoneNumber === call.caller ? call.callee : call.caller;
        const recipientUser = connectedUsers.get(recipient);

        if (recipientUser) {
            io.to(recipientUser.socketId).emit('offer', { callId, sdp });
        }
    });

    // SDP Answer
    socket.on('answer', (data) => {
        const { callId, sdp } = data;
        const call = activeCalls.get(callId);

        if (!call) return;

        // Forward to caller
        const recipient = socket.phoneNumber === call.caller ? call.callee : call.caller;
        const recipientUser = connectedUsers.get(recipient);

        if (recipientUser) {
            io.to(recipientUser.socketId).emit('answer', { callId, sdp });
        }
    });

    // ICE Candidate
    socket.on('ice-candidate', (data) => {
        const { callId, candidate } = data;
        const call = activeCalls.get(callId);

        if (!call) return;

        // Forward to other party
        const recipient = socket.phoneNumber === call.caller ? call.callee : call.caller;
        const recipientUser = connectedUsers.get(recipient);

        if (recipientUser) {
            io.to(recipientUser.socketId).emit('ice-candidate', { callId, candidate });
        }
    });

    // Disconnect
    socket.on('disconnect', () => {
        console.log(`User disconnected: ${socket.phoneNumber}`);

        // Remove from connected users
        connectedUsers.delete(socket.phoneNumber);

        // End any active calls
        for (const [callId, call] of activeCalls.entries()) {
            if (call.caller === socket.phoneNumber || call.callee === socket.phoneNumber) {
                const otherParty = socket.phoneNumber === call.caller ? call.callee : call.caller;
                const otherUser = connectedUsers.get(otherParty);

                if (otherUser) {
                    io.to(otherUser.socketId).emit('call-ended', {
                        callId,
                        reason: 'disconnect'
                    });
                }

                activeCalls.delete(callId);
            }
        }
    });
});

// Send VoIP push notification
async function sendVoIPPush(deviceToken, payload) {
    const notification = new apn.Notification({
        topic: 'com.yourapp.voip',
        payload: {
            callId: payload.callId,
            caller: payload.caller,
            hasVideo: payload.hasVideo
        },
        pushType: 'voip'
    });

    try {
        const result = await apnProvider.send(notification, deviceToken);
        console.log('Push notification sent:', result);
    } catch (error) {
        console.error('Push notification error:', error);
    }
}

// Health check endpoint
app.get('/health', (req, res) => {
    res.json({
        status: 'ok',
        connectedUsers: connectedUsers.size,
        activeCalls: activeCalls.size
    });
});

// Start server
const PORT = process.env.PORT || 3000;
server.listen(PORT, () => {
    console.log(`Signaling server running on port ${PORT}`);
});

// Graceful shutdown
process.on('SIGTERM', async () => {
    console.log('SIGTERM received, shutting down gracefully');
    server.close(() => {
        console.log('Server closed');
        process.exit(0);
    });
});
```

### package.json

```json
{
  "name": "webrtc-signaling-server",
  "version": "1.0.0",
  "description": "WebRTC Signaling Server for iOS Dialer App",
  "main": "server.js",
  "scripts": {
    "start": "node server.js",
    "dev": "nodemon server.js"
  },
  "dependencies": {
    "express": "^4.18.2",
    "socket.io": "^4.6.0",
    "jsonwebtoken": "^9.0.2",
    "redis": "^4.6.5",
    "apn": "^2.2.0",
    "dotenv": "^16.0.3"
  },
  "devDependencies": {
    "nodemon": "^2.0.22"
  }
}
```

## iOS Client Implementation

### SignalingClient

```swift
import Foundation
import SocketIO

protocol SignalingClientDelegate: AnyObject {
    func signalingClient(_ client: SignalingClient, didReceiveIncomingCall callId: String, from: String, hasVideo: Bool)
    func signalingClient(_ client: SignalingClient, callWasAnswered callId: String)
    func signalingClient(_ client: SignalingClient, callWasRejected callId: String)
    func signalingClient(_ client: SignalingClient, callDidEnd callId: String)
    func signalingClient(_ client: SignalingClient, didReceiveOffer sdp: String, forCall callId: String)
    func signalingClient(_ client: SignalingClient, didReceiveAnswer sdp: String, forCall callId: String)
    func signalingClient(_ client: SignalingClient, didReceiveIceCandidate candidate: [String: Any], forCall callId: String)
}

class SignalingClient {

    weak var delegate: SignalingClientDelegate?

    private var manager: SocketManager!
    private var socket: SocketIOClient!

    private let serverURL = "wss://your-server.com"
    private var authToken: String?

    init(authToken: String) {
        self.authToken = authToken
        setupSocket()
    }

    private func setupSocket() {
        manager = SocketManager(
            socketURL: URL(string: serverURL)!,
            config: [
                .log(false),
                .compress,
                .forceWebsockets(true),
                .reconnects(true),
                .reconnectAttempts(-1),
                .reconnectWait(2)
            ]
        )

        socket = manager.socket(forNamespace: "/")
        socket.setReconnecting(reason: "transport closed")

        setupHandlers()
    }

    private func setupHandlers() {
        socket.on(clientEvent: .connect) { [weak self] data, ack in
            print("SignalingClient: Connected")
            self?.register()
        }

        socket.on(clientEvent: .disconnect) { data, ack in
            print("SignalingClient: Disconnected")
        }

        socket.on(clientEvent: .error) { data, ack in
            print("SignalingClient: Error - \(data)")
        }

        socket.on("registered") { [weak self] data, ack in
            print("SignalingClient: Registered successfully")
        }

        socket.on("incoming-call") { [weak self] data, ack in
            guard let self = self,
                  let dict = data.first as? [String: Any],
                  let callId = dict["callId"] as? String,
                  let from = dict["from"] as? String,
                  let hasVideo = dict["hasVideo"] as? Bool else { return }

            self.delegate?.signalingClient(self, didReceiveIncomingCall: callId, from: from, hasVideo: hasVideo)
        }

        socket.on("call-answered") { [weak self] data, ack in
            guard let self = self,
                  let dict = data.first as? [String: Any],
                  let callId = dict["callId"] as? String else { return }

            self.delegate?.signalingClient(self, callWasAnswered: callId)
        }

        socket.on("call-rejected") { [weak self] data, ack in
            guard let self = self,
                  let dict = data.first as? [String: Any],
                  let callId = dict["callId"] as? String else { return }

            self.delegate?.signalingClient(self, callWasRejected: callId)
        }

        socket.on("call-ended") { [weak self] data, ack in
            guard let self = self,
                  let dict = data.first as? [String: Any],
                  let callId = dict["callId"] as? String else { return }

            self.delegate?.signalingClient(self, callDidEnd: callId)
        }

        socket.on("offer") { [weak self] data, ack in
            guard let self = self,
                  let dict = data.first as? [String: Any],
                  let callId = dict["callId"] as? String,
                  let sdp = dict["sdp"] as? String else { return }

            self.delegate?.signalingClient(self, didReceiveOffer: sdp, forCall: callId)
        }

        socket.on("answer") { [weak self] data, ack in
            guard let self = self,
                  let dict = data.first as? [String: Any],
                  let callId = dict["callId"] as? String,
                  let sdp = dict["sdp"] as? String else { return }

            self.delegate?.signalingClient(self, didReceiveAnswer: sdp, forCall: callId)
        }

        socket.on("ice-candidate") { [weak self] data, ack in
            guard let self = self,
                  let dict = data.first as? [String: Any],
                  let callId = dict["callId"] as? String,
                  let candidate = dict["candidate"] as? [String: Any] else { return }

            self.delegate?.signalingClient(self, didReceiveIceCandidate: candidate, forCall: callId)
        }
    }

    // MARK: - Connection

    func connect() {
        socket.connect(withPayload: ["token": authToken ?? ""])
    }

    func disconnect() {
        socket.disconnect()
    }

    private func register() {
        let deviceToken = UserDefaults.standard.string(forKey: "voipDeviceToken") ?? ""

        socket.emit("register", [
            "deviceToken": deviceToken
        ])
    }

    // MARK: - Call Signaling

    func initiateCall(to phoneNumber: String, callId: String, hasVideo: Bool) {
        socket.emit("call-initiate", [
            "to": phoneNumber,
            "callId": callId,
            "hasVideo": hasVideo
        ])
    }

    func acceptCall(callId: String) {
        socket.emit("call-accept", [
            "callId": callId
        ])
    }

    func rejectCall(callId: String, reason: String? = nil) {
        socket.emit("call-reject", [
            "callId": callId,
            "reason": reason ?? ""
        ])
    }

    func endCall(callId: String) {
        socket.emit("call-end", [
            "callId": callId
        ])
    }

    // MARK: - WebRTC Signaling

    func sendOffer(sdp: String, forCall callId: String) {
        socket.emit("offer", [
            "callId": callId,
            "sdp": sdp
        ])
    }

    func sendAnswer(sdp: String, forCall callId: String) {
        socket.emit("answer", [
            "callId": callId,
            "sdp": sdp
        ])
    }

    func sendIceCandidate(_ candidate: [String: Any], forCall callId: String) {
        socket.emit("ice-candidate", [
            "callId": callId,
            "candidate": candidate
        ])
    }
}
```

## Scalability Considerations

### Multi-Server Setup with Redis

For horizontal scaling:

```javascript
// Use Redis adapter for Socket.io
const { createAdapter } = require('@socket.io/redis-adapter');
const { createClient } = require('redis');

const pubClient = createClient({ url: process.env.REDIS_URL });
const subClient = pubClient.duplicate();

Promise.all([pubClient.connect(), subClient.connect()]).then(() => {
    io.adapter(createAdapter(pubClient, subClient));
});
```

### Load Balancing

Use sticky sessions in your load balancer:

```nginx
# Nginx configuration
upstream signaling_servers {
    ip_hash;  # Sticky sessions
    server server1:3000;
    server server2:3000;
    server server3:3000;
}

server {
    listen 443 ssl;
    server_name signaling.yourapp.com;

    location / {
        proxy_pass http://signaling_servers;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
    }
}
```

## Security Best Practices

1. **Use WSS (WebSocket Secure)** - Always use TLS
2. **Authenticate connections** - JWT tokens
3. **Validate all messages** - Don't trust client input
4. **Rate limiting** - Prevent abuse
5. **CORS configuration** - Restrict origins in production
6. **Regular security updates** - Keep dependencies updated

## Monitoring & Logging

```javascript
// Add metrics
const prometheus = require('prom-client');

const connectedUsersGauge = new prometheus.Gauge({
    name: 'signaling_connected_users',
    help: 'Number of connected users'
});

const activeCallsGauge = new prometheus.Gauge({
    name: 'signaling_active_calls',
    help: 'Number of active calls'
});

// Update metrics
setInterval(() => {
    connectedUsersGauge.set(connectedUsers.size);
    activeCallsGauge.set(activeCalls.size);
}, 5000);

// Metrics endpoint
app.get('/metrics', async (req, res) => {
    res.set('Content-Type', prometheus.register.contentType);
    res.end(await prometheus.register.metrics());
});
```

## Testing

### Unit Tests

```javascript
const { describe, it, beforeEach } = require('mocha');
const { expect } = require('chai');
const io = require('socket.io-client');

describe('Signaling Server', () => {
    let clientSocket;

    beforeEach((done) => {
        clientSocket = io('http://localhost:3000', {
            auth: { token: 'test-token' }
        });
        clientSocket.on('connect', done);
    });

    it('should register successfully', (done) => {
        clientSocket.emit('register', { deviceToken: 'test-token' });

        clientSocket.on('registered', (data) => {
            expect(data.success).to.be.true;
            done();
        });
    });

    // More tests...
});
```

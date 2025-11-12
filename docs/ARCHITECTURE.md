# iOS WebRTC Dialer Application - Architecture Overview

## Project Vision

A native iOS application that provides a seamless phone dialing experience using WebRTC for peer-to-peer voice and video calls. Users are identified by their phone numbers and the app integrates deeply with iOS native features (CallKit, Contacts, VoIP Push Notifications).

## High-Level Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    iOS Application                           │
│                                                              │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐      │
│  │   CallKit    │  │   Contacts   │  │  Dialer UI   │      │
│  │  Integration │  │  Framework   │  │   (Native)   │      │
│  └──────────────┘  └──────────────┘  └──────────────┘      │
│                                                              │
│  ┌──────────────────────────────────────────────────────┐  │
│  │         WebRTC Engine (GoogleWebRTC)                  │  │
│  │  • RTCPeerConnection                                  │  │
│  │  • Audio/Video Capture & Rendering                    │  │
│  │  • ICE Candidate Management                           │  │
│  └──────────────────────────────────────────────────────┘  │
│                                                              │
│  ┌──────────────────────────────────────────────────────┐  │
│  │         Signaling Layer (WebSocket)                   │  │
│  │  • Call Initiation/Termination                        │  │
│  │  • SDP Offer/Answer Exchange                          │  │
│  │  • ICE Candidate Exchange                             │  │
│  └──────────────────────────────────────────────────────┘  │
│                                                              │
│  ┌──────────────────────────────────────────────────────┐  │
│  │         Push Notification Handler (VoIP)              │  │
│  │  • PushKit Integration                                │  │
│  │  • Background Call Wakeup                             │  │
│  └──────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
                           │
                           │ WebSocket + REST API
                           ▼
┌─────────────────────────────────────────────────────────────┐
│                  Backend Services                            │
│                                                              │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐      │
│  │  Signaling   │  │     User     │  │    TURN/     │      │
│  │   Server     │  │   Registry   │  │  STUN Server │      │
│  │ (WebSocket)  │  │   (Phone #)  │  │   (NAT Trav) │      │
│  └──────────────┘  └──────────────┘  └──────────────┘      │
│                                                              │
│  ┌──────────────┐  ┌──────────────┐                        │
│  │   APNs Push  │  │   Auth &     │                        │
│  │   Gateway    │  │   Session    │                        │
│  └──────────────┘  └──────────────┘                        │
└─────────────────────────────────────────────────────────────┘
```

## Core Components

### 1. iOS Application Layer

#### 1.1 CallKit Integration
- Provides native iOS call interface
- Shows incoming calls on lock screen
- Integrates with system call history
- Handles call states (incoming, outgoing, connected, ended)
- Provides native call controls (mute, speaker, hold)

#### 1.2 Contacts Framework
- Reads phone contacts with user permission
- Displays contacts in dialer interface
- Matches incoming calls with contact names
- Provides contact search functionality

#### 1.3 Native Dialer UI
- Dial pad for manual number entry
- Recent calls list
- Contacts browser
- Search functionality
- Call/Video call buttons

#### 1.4 WebRTC Engine
- Peer-to-peer audio/video communication
- Uses Google's WebRTC library for iOS
- Manages RTCPeerConnection lifecycle
- Handles media capture and rendering
- ICE candidate gathering and exchange

#### 1.5 Signaling Client
- WebSocket-based real-time communication
- Handles call setup/teardown signaling
- Exchanges SDP offers/answers
- Transmits ICE candidates
- Manages user presence

#### 1.6 VoIP Push Notifications
- PushKit integration for background call reception
- Wakes app from terminated state
- Triggers CallKit incoming call UI
- Low-latency notification delivery

### 2. Backend Services Layer

#### 2.1 Signaling Server
- WebSocket server for real-time signaling
- Routes messages between peers
- Maintains active user connections
- Handles presence information
- Technology options: Node.js (Socket.io), Go, Python (asyncio)

#### 2.2 User Registry
- Phone number-based user identification
- User authentication (SMS verification)
- Device registration (for push notifications)
- User availability status
- Database: PostgreSQL or MongoDB

#### 2.3 STUN/TURN Servers
- STUN for NAT traversal and peer discovery
- TURN for relay when direct connection fails
- Can use: coturn, Google's STUN servers, Twilio TURN

#### 2.4 APNs Push Gateway
- Sends VoIP push notifications via Apple Push Notification service
- Requires APNs certificates/keys
- Manages device tokens

#### 2.5 Authentication Service
- Phone number verification (SMS/OTP)
- JWT token generation
- Session management
- Could integrate: Twilio Verify, Firebase Auth

## Data Flow

### Outgoing Call Flow

1. **User Initiates Call**
   - User selects contact or enters phone number
   - Taps voice/video call button
   - App checks user availability via signaling server

2. **CallKit Setup**
   - App reports outgoing call to CallKit
   - Native call UI appears
   - System audio routes to earpiece/speaker

3. **WebRTC Setup**
   - Create RTCPeerConnection
   - Add local media tracks (audio/video)
   - Generate SDP offer

4. **Signaling**
   - Send call initiation to signaling server
   - Server routes to recipient's device
   - Recipient receives VoIP push notification

5. **Connection Establishment**
   - Exchange SDP offer/answer
   - Exchange ICE candidates
   - Establish peer-to-peer connection

6. **Active Call**
   - Media flows directly between peers (or via TURN)
   - CallKit manages call state
   - UI shows call duration, controls

### Incoming Call Flow

1. **Push Notification**
   - Signaling server sends VoIP push
   - PushKit wakes app (even if terminated)
   - App receives caller information

2. **CallKit Incoming Call**
   - App reports incoming call to CallKit
   - Native incoming call UI appears (lock screen compatible)
   - Ringtone plays

3. **User Accepts**
   - CallKit notifies app of acceptance
   - App connects to signaling server
   - Sends call acceptance signal

4. **WebRTC Setup**
   - Create RTCPeerConnection
   - Receive SDP offer from caller
   - Generate SDP answer
   - Exchange ICE candidates

5. **Connection Establishment**
   - Establish peer-to-peer connection
   - Start media flow

6. **Active Call**
   - Same as outgoing call flow

## Technology Stack

### iOS Application
- **Language**: Swift 5.9+
- **Minimum iOS Version**: iOS 15.0+
- **WebRTC**: GoogleWebRTC (via CocoaPods or SPM)
- **UI Framework**: UIKit or SwiftUI
- **Frameworks**:
  - CallKit
  - Contacts
  - ContactsUI
  - PushKit
  - AVFoundation
  - Network

### Backend (Recommended)
- **Signaling Server**: Node.js + Socket.io or Go + WebSockets
- **API Server**: Node.js (Express) or Go (Gin)
- **Database**: PostgreSQL for user data
- **Cache/Session**: Redis
- **TURN/STUN**: coturn server
- **Push Notifications**: APNs via HTTP/2

### Infrastructure
- **Hosting**: AWS, Google Cloud, or Digital Ocean
- **WebSocket**: Load balanced with sticky sessions
- **Database**: Managed PostgreSQL (RDS, Cloud SQL)
- **CDN**: CloudFront or Cloudflare (for web assets if any)

## Security Considerations

### 1. Media Encryption
- WebRTC provides built-in DTLS-SRTP encryption
- End-to-end encrypted by default
- No server can decrypt media

### 2. Signaling Security
- Use WSS (WebSocket Secure) with TLS 1.3
- Authenticate users with JWT tokens
- Validate all signaling messages

### 3. Authentication
- Phone number verification via SMS OTP
- Secure token storage in iOS Keychain
- Token refresh mechanism
- Rate limiting on authentication attempts

### 4. Privacy
- Request minimum necessary permissions
- Clear permission request explanations
- Contact data stays on device
- No unnecessary data collection

### 5. Network Security
- Certificate pinning for API connections
- Input validation on all user data
- Protection against call injection attacks

## Scalability Considerations

### Signaling Server
- Horizontal scaling with WebSocket sticky sessions
- Redis pub/sub for cross-server message routing
- Load balancer with session affinity

### Database
- Read replicas for user queries
- Connection pooling
- Indexed phone number lookups

### TURN Server
- Multiple TURN servers in different regions
- Load balancing across TURN servers
- Monitoring bandwidth usage

## Development Phases

### Phase 1: Foundation (Weeks 1-2)
- Xcode project setup
- WebRTC integration
- Basic UI scaffolding
- Backend signaling server prototype

### Phase 2: Core Features (Weeks 3-5)
- Phone number authentication
- CallKit integration
- Basic WebRTC calling (audio only)
- Signaling implementation

### Phase 3: Enhanced Features (Weeks 6-7)
- Video calling
- Contacts integration
- VoIP push notifications
- Call history

### Phase 4: Polish & Testing (Weeks 8-9)
- UI/UX refinement
- End-to-end testing
- Performance optimization
- Bug fixes

### Phase 5: Production Ready (Week 10)
- Security audit
- Load testing
- App Store preparation
- Documentation

## Key Challenges & Solutions

### Challenge 1: NAT Traversal
- **Solution**: Implement STUN/TURN servers, use multiple ICE candidates

### Challenge 2: Background Call Reception
- **Solution**: VoIP push notifications with PushKit, maintain signaling connection

### Challenge 3: CallKit Integration Complexity
- **Solution**: Proper state management, follow Apple's CXProvider delegate pattern

### Challenge 4: Network Reliability
- **Solution**: WebSocket reconnection logic, call quality indicators, fallback mechanisms

### Challenge 5: Contact Matching
- **Solution**: Normalize phone numbers (E.164 format), efficient lookup algorithms

## Success Metrics

- Call connection success rate > 95%
- Call quality (MOS score) > 4.0
- Time to answer < 2 seconds
- Push notification delivery < 1 second
- App crash rate < 0.1%
- User retention after 30 days

## Future Enhancements

- Group calling
- Screen sharing
- Call recording (with consent)
- End-to-end encrypted messaging
- Voicemail
- Call forwarding
- International calling optimization
- Accessibility features
- iPad support
- Apple Watch complication

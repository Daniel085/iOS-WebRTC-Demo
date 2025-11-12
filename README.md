# iOS WebRTC Dialer Application

A native iOS application that provides a seamless phone dialing experience using WebRTC for peer-to-peer voice and video calls. Users are identified by their phone numbers and the app integrates deeply with iOS native features including CallKit, Contacts, and VoIP Push Notifications.

## Features

- **Native Dialer Experience**: Looks and feels like the iOS Phone app
- **Voice & Video Calls**: High-quality WebRTC-based calls
- **CallKit Integration**: Native iOS call interface on lock screen
- **Contacts Integration**: Access to phone contacts
- **Phone Number Authentication**: SMS-based user verification
- **VoIP Push Notifications**: Receive calls even when app is terminated
- **Call History**: Track recent calls
- **Native UI**: SwiftUI-based modern interface

## Documentation

### 📖 Start Here

- **[HOW_IT_WORKS.md](./docs/HOW_IT_WORKS.md)** - 🌟 **Complete walkthrough** of how the entire app works from start to finish
- **[GETTING_STARTED.md](./GETTING_STARTED.md)** - Quick start guide for developers
- **[SETUP_GUIDE.md](./docs/SETUP_GUIDE.md)** - Detailed setup instructions with dependencies

### 📚 Technical Documentation

Comprehensive technical guides available in the `/docs` folder:

- **[ARCHITECTURE.md](./docs/ARCHITECTURE.md)** - Overall system architecture and design
- **[WEBRTC_INTEGRATION.md](./docs/WEBRTC_INTEGRATION.md)** - WebRTC implementation guide
- **[CALLKIT_INTEGRATION.md](./docs/CALLKIT_INTEGRATION.md)** - CallKit integration details
- **[CONTACTS_INTEGRATION.md](./docs/CONTACTS_INTEGRATION.md)** - Contacts framework guide
- **[SIGNALING_SERVER.md](./docs/SIGNALING_SERVER.md)** - Signaling server architecture
- **[AUTHENTICATION.md](./docs/AUTHENTICATION.md)** - Phone number authentication
- **[VOIP_PUSH_NOTIFICATIONS.md](./docs/VOIP_PUSH_NOTIFICATIONS.md)** - VoIP push setup
- **[UI_UX_FLOW.md](./docs/UI_UX_FLOW.md)** - UI/UX design and flows
- **[SECURITY.md](./docs/SECURITY.md)** - Security best practices
- **[IMPLEMENTATION_ROADMAP.md](./docs/IMPLEMENTATION_ROADMAP.md)** - Step-by-step implementation plan

## Technology Stack

### iOS Application
- **Language**: Swift 5.9+
- **Minimum iOS Version**: iOS 15.0+
- **UI Framework**: SwiftUI
- **WebRTC**: GoogleWebRTC
- **Frameworks**: CallKit, Contacts, PushKit, AVFoundation

### Backend
- **Signaling Server**: Node.js + Socket.io
- **API Server**: Node.js + Express
- **Database**: PostgreSQL
- **Push Notifications**: APNs
- **TURN/STUN**: coturn

## Getting Started

### Prerequisites

**For iOS Development:**
- macOS 12.0+ with Xcode 14+
- CocoaPods: `sudo gem install cocoapods`
- Apple Developer Account ($99/year for VoIP features)

**For Backend Development (Optional):**
- Node.js 18+
- PostgreSQL 13+
- Twilio Account (for SMS verification)

### Installation & Running

#### Option 1: Run in Xcode Simulator (Quickest)

Perfect for testing UI and development without backend:

```bash
# 1. Clone the repository
git clone <your-repo-url>
cd iOS-WebRTC-Demo/ios/WebRTCDialer

# 2. Install dependencies (takes 2-5 minutes first time)
pod install

# 3. Open in Xcode
open WebRTCDialer.xcworkspace

# 4. In Xcode:
#    - Select iPhone simulator (iPhone 14 Pro or later)
#    - Press ▶️ Run button (or ⌘R)
```

**First time?** See **[ios/SIMULATOR_SETUP.md](./ios/SIMULATOR_SETUP.md)** for detailed setup including creating the Xcode project.

**What works in simulator:**
- ✅ Full UI navigation and screens
- ✅ Authentication flow UI
- ✅ Tab bar, keypad, contacts, settings
- ❌ VoIP pushes (needs physical device)
- ❌ Actual calls (needs backend + device)

#### Option 2: Run on Physical Device (Full Features)

For testing VoIP push notifications and real calls:

```bash
# Same steps as simulator, but:
# - Connect iPhone via USB
# - In Xcode: Select your iPhone instead of simulator
# - Configure signing with your Apple Developer account
# - Build and run
```

See **[docs/XCODE_SETUP.md](./docs/XCODE_SETUP.md)** for complete device setup.

#### Option 3: With Backend Server (Full Stack)

To enable authentication and calling:

**1. Set up Mock Backend (Quick Test):**
```bash
cd backend
npm init -y && npm install express

# Create mock-server.js:
cat > mock-server.js << 'EOF'
const express = require('express');
const app = express();
app.use(express.json());

app.post('/auth/send-code', (req, res) => {
    console.log('Send code to:', req.body.phoneNumber);
    res.json({ success: true });
});

app.post('/auth/verify-code', (req, res) => {
    res.json({
        success: true,
        token: 'mock-token-' + Date.now(),
        user: { id: 'user-123', phoneNumber: req.body.phoneNumber }
    });
});

app.listen(3000, () => console.log('Mock server on http://localhost:3000'));
EOF

# Run mock server
node mock-server.js
```

**2. Update iOS app to use backend:**
```swift
// In ios/WebRTCDialer/WebRTCDialer/Utilities/Constants.swift
enum API {
    static let baseURL = "http://localhost:3000"
    static let signalingURL = "ws://localhost:3000"
}
```

**3. Run app** (it will now connect to your backend!)

### Quick Start Summary

```bash
# Minimum to see the app run:
cd iOS-WebRTC-Demo/ios/WebRTCDialer
pod install
open WebRTCDialer.xcworkspace
# Press ▶️ in Xcode

# To test with mock authentication:
cd ../../backend
npm init -y && npm install express
node mock-server.js  # (create file above first)
# Then run iOS app
```

### Next Steps

1. **Understand the System**: Read [HOW_IT_WORKS.md](./docs/HOW_IT_WORKS.md)
2. **Set Up for Development**: Follow [XCODE_SETUP.md](./docs/XCODE_SETUP.md)
3. **Build Complete Backend**: See [SIGNALING_SERVER.md](./docs/SIGNALING_SERVER.md)
4. **Implement Features**: Follow [IMPLEMENTATION_ROADMAP.md](./docs/IMPLEMENTATION_ROADMAP.md)

## Project Structure

```
iOS-WebRTC-Demo/
├── docs/                           # Comprehensive documentation
│   ├── ARCHITECTURE.md
│   ├── WEBRTC_INTEGRATION.md
│   ├── CALLKIT_INTEGRATION.md
│   ├── CONTACTS_INTEGRATION.md
│   ├── SIGNALING_SERVER.md
│   ├── AUTHENTICATION.md
│   ├── VOIP_PUSH_NOTIFICATIONS.md
│   ├── UI_UX_FLOW.md
│   ├── SECURITY.md
│   └── IMPLEMENTATION_ROADMAP.md
├── ios/                            # iOS application (to be created)
│   └── WebRTCDialer/
└── backend/                        # Backend services (to be created)
    ├── signaling-server/
    └── api-server/
```

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                    iOS Application                           │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐      │
│  │   CallKit    │  │   Contacts   │  │  Dialer UI   │      │
│  └──────────────┘  └──────────────┘  └──────────────┘      │
│  ┌──────────────────────────────────────────────────────┐  │
│  │         WebRTC Engine (GoogleWebRTC)                  │  │
│  └──────────────────────────────────────────────────────┘  │
│  ┌──────────────────────────────────────────────────────┐  │
│  │         Signaling Layer (WebSocket)                   │  │
│  └──────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────┐
│                  Backend Services                            │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐      │
│  │  Signaling   │  │     User     │  │    TURN/     │      │
│  │   Server     │  │   Registry   │  │  STUN Server │      │
│  └──────────────┘  └──────────────┘  └──────────────┘      │
└─────────────────────────────────────────────────────────────┘
```

## Key Features Explained

### CallKit Integration
Provides native iOS calling experience:
- Incoming calls appear on lock screen
- Integrates with system call history
- Native call controls (mute, speaker, etc.)
- Works with CarPlay and Bluetooth devices

### WebRTC
Enables peer-to-peer communication:
- High-quality audio and video
- End-to-end encryption (DTLS-SRTP)
- NAT traversal (STUN/TURN)
- Low latency

### VoIP Push Notifications
Allows app to receive calls when not running:
- Wakes app from terminated state
- Low-latency delivery
- Triggers CallKit UI
- Required for production calling apps

## Development Timeline

Following the implementation roadmap:
- **Phase 1** (2 weeks): Foundation setup
- **Phase 2** (3 weeks): Core calling features
- **Phase 3** (2 weeks): Enhanced features
- **Phase 4** (2 weeks): Testing and polish
- **Phase 5** (1 week): Production preparation

**Total: 10 weeks**

## Security

This application implements multiple security layers:
- TLS 1.3 for all network communication
- JWT-based authentication
- Keychain storage for sensitive data
- WebRTC encryption (DTLS-SRTP)
- Input validation and sanitization
- Rate limiting

See [SECURITY.md](./docs/SECURITY.md) for detailed security practices.

## Contributing

This is a demonstration/educational project. Contributions are welcome!

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Submit a pull request

## License

[To be determined - Add your license here]

## Support

For questions or issues:
- Review the documentation in `/docs`
- Check the [Implementation Roadmap](./docs/IMPLEMENTATION_ROADMAP.md)
- Open an issue on GitHub

## External Dependencies (Not Included)

This demo includes the **iOS application code** and **documentation**. The following external components are **required but not included** and must be set up separately:

### 1. Backend Signaling Server ⚠️ **REQUIRED**

**What it does:** Routes call setup messages between users, manages presence

**Technology:** Node.js + Socket.io (recommended) or Go + WebSockets

**Status:** 📄 **Documented** (not built)
- See [SIGNALING_SERVER.md](./docs/SIGNALING_SERVER.md) for implementation guide
- Sample code provided in documentation
- Estimated setup time: 4-8 hours

**Quick Mock Server** (for testing):
```bash
# See "Getting Started" section above for mock server code
cd backend && node mock-server.js
```

**Production Server Requirements:**
- WebSocket support for real-time signaling
- REST API for authentication
- Database for user storage
- Handles SDP and ICE candidate exchange

### 2. STUN/TURN Servers ⚠️ **REQUIRED for Production**

**What it does:** Helps devices discover their public IP (STUN) and relay media when direct connection fails (TURN)

**Options:**

**Option A: Free Public STUN** (development only)
```swift
// Already configured in Constants.swift
config.iceServers = [
    RTCIceServer(urlStrings: ["stun:stun.l.google.com:19302"])
]
```
- ✅ Free
- ✅ Works for development
- ❌ No TURN relay (calls may fail behind strict firewalls)
- ❌ ~30% of calls need TURN in production

**Option B: Self-Hosted TURN** (production recommended)
- Software: [coturn](https://github.com/coturn/coturn)
- Cost: Server hosting (~$20-50/month)
- Setup time: 2-4 hours
- See [SIGNALING_SERVER.md](./docs/SIGNALING_SERVER.md) for configuration

**Option C: Managed Service** (easiest for production)
- [Twilio TURN](https://www.twilio.com/stun-turn): ~$0.0004/min
- [Xirsys](https://xirsys.com/): $10-50/month
- Setup time: 30 minutes
- ✅ Recommended for production

### 3. SMS Verification Service ⚠️ **REQUIRED**

**What it does:** Sends SMS verification codes for phone number authentication

**Options:**

**Option A: Twilio Verify** (recommended)
- Cost: ~$0.05 per verification
- Setup: [AUTHENTICATION.md](./docs/AUTHENTICATION.md)
- Free trial: $15 credit

**Option B: Firebase Phone Auth**
- Cost: Free tier available
- Easier integration
- See [Firebase Phone Auth docs](https://firebase.google.com/docs/auth/ios/phone-auth)

**Option C: Custom SMS Gateway**
- Use your own SMS provider
- Implement custom verification logic

**For Testing:**
- Mock server (see Getting Started) - free
- Accepts any verification code

### 4. Database 📋 **REQUIRED**

**What it does:** Stores users, device tokens, call history

**Recommended:** PostgreSQL
- See [SIGNALING_SERVER.md](./docs/SIGNALING_SERVER.md) for schema
- Alternatives: MySQL, MongoDB

**For Testing:**
- In-memory storage (mock server)
- SQLite (local development)

### 5. Apple Push Notification Service (APNs) ⚠️ **REQUIRED for VoIP**

**What it does:** Delivers VoIP push notifications to wake app for incoming calls

**Requirements:**
- Apple Developer Account ($99/year)
- APNs certificate or key (.p8 file)
- VoIP entitlement enabled

**Setup:**
- See [VOIP_PUSH_NOTIFICATIONS.md](./docs/VOIP_PUSH_NOTIFICATIONS.md)
- Generate .p8 key in Apple Developer portal
- Configure in backend

**Cost:** Free (after Developer account)

### 6. Apple Developer Account 💰 **REQUIRED for Device Testing**

**What it does:** Allows app installation on devices, VoIP push notifications

**Cost:** $99/year

**What you get:**
- Install app on physical devices
- VoIP push notifications
- App Store distribution
- TestFlight beta testing

**Free Alternative:**
- Free account (limited)
- Simulator testing only
- No VoIP pushes
- 7-day device installations

---

## What's Included vs. What You Need

### ✅ Included in This Repo

- **iOS Application Code**
  - Complete Swift/SwiftUI source code
  - Authentication flow UI
  - CallKit integration
  - WebRTC client implementation
  - VoIP push handling
  - All views and services

- **Comprehensive Documentation**
  - 12 detailed guides
  - Architecture diagrams
  - Code examples
  - Security best practices
  - 10-week implementation roadmap

- **Dependencies Configuration**
  - Podfile for CocoaPods
  - WebRTC, Socket.IO, PhoneNumberKit

### ⚠️ Required But Not Included

| Component | Status | Estimated Cost | Setup Time |
|-----------|--------|----------------|------------|
| Backend Signaling Server | 📄 Documented | $10-50/mo hosting | 4-8 hours |
| STUN Server | ✅ Free (Google) | Free | 0 min |
| TURN Server | 📄 Documented | $20-50/mo OR $0.0004/min | 2-4 hours |
| SMS Service (Twilio) | 📄 Documented | $0.05/verification | 1 hour |
| Database (PostgreSQL) | 📄 Schema provided | $10-30/mo | 1-2 hours |
| APNs Setup | 📄 Documented | Free* | 1 hour |
| Apple Developer Account | ❌ Purchase needed | $99/year* | 15 min |

*Required for VoIP pushes and device testing

### 💰 Total Cost Estimate

**Development/Testing:**
- Free (using mock server + simulator)
- No external costs needed to run and test UI

**Production (Small Scale < 1000 users):**
- Apple Developer: $99/year
- Hosting (backend + DB): $30-80/month
- TURN server: $20/month OR pay-per-use
- SMS: ~$50/month (1000 verifications)
- **Total: ~$99 + $100-150/month**

**Production (Large Scale > 10,000 users):**
- Same base costs
- Scaled hosting: $200-500/month
- TURN bandwidth: $100-500/month
- SMS: ~$500/month (10,000 verifications)
- **Total: ~$99 + $800-1500/month**

---

## Minimal Setup (Start Here)

To get started with **minimal setup** (no costs):

```bash
# 1. Clone repo
git clone <repo-url>
cd iOS-WebRTC-Demo

# 2. Install iOS dependencies
cd ios/WebRTCDialer
pod install

# 3. Open in Xcode
open WebRTCDialer.xcworkspace

# 4. Run in simulator
# Select iPhone 14 Pro simulator, press ▶️
```

**You now have:**
- ✅ Working iOS app UI
- ✅ All screens and navigation
- ✅ Can test interface

**To enable authentication** (15 min setup):
```bash
# Create mock backend
cd backend
npm init -y && npm install express
# Create mock-server.js (see Getting Started section)
node mock-server.js

# Update iOS app Constants.swift with http://localhost:3000
# Run app - authentication now works!
```

**To enable real calls** (full production setup):
- Follow [IMPLEMENTATION_ROADMAP.md](./docs/IMPLEMENTATION_ROADMAP.md)
- Set up all external dependencies listed above
- Estimated time: 2-3 days for full stack

---

## Roadmap

Future enhancements:
- Group calling
- Screen sharing
- End-to-end encrypted messaging
- Call recording
- Voicemail
- iPad and Mac Catalyst support

## Acknowledgments

- Google WebRTC team
- Apple CallKit documentation
- Socket.io team
- Open source community

---

## Support & Resources

- **Documentation**: See `/docs` folder for 12 detailed guides
- **Issues**: Check troubleshooting sections in each guide
- **Questions**: Review [HOW_IT_WORKS.md](./docs/HOW_IT_WORKS.md) for system overview

**Ready to build?** Start with the [Quick Start](#installation--running) above! 🚀

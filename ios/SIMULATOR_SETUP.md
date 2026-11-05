# Quick Simulator Setup

**TL;DR**: Steps to run the app in Xcode Simulator

## Prerequisites

1. macOS with Xcode 14+ installed (Xcode 15+ recommended)
2. **No additional tools required** - we use Swift Package Manager

## Setup (First Time Only)

### 1. Create Xcode Project

In Xcode:
1. File → New → Project
2. Choose: iOS → App
3. Configure:
   - Product Name: `WebRTCDialer`
   - Interface: SwiftUI
   - Language: Swift
4. Save in: `iOS-WebRTC-Demo/ios/` folder

### 2. Add Source Files

1. Delete default files Xcode created:
   - `ContentView.swift`
   - `WebRTCDialerApp.swift`

2. Add our files:
   - Drag these folders from Finder into Xcode:
     - `App/`
     - `Models/`
     - `Views/`
     - `Services/`
     - `Utilities/`
   - Check: "Copy items if needed"
   - Check: "Create groups"

3. Replace `Info.plist` with our version

### 3. Add Swift Package Dependencies

Keep Xcode open, then add packages:

1. **File → Add Package Dependencies...**

2. **Add WebRTC**:
   - URL: `https://github.com/stasel/WebRTC.git`
   - Dependency: Up to Next Major → `114.0.0`
   - Click Add Package

3. **Add Socket.IO**:
   - URL: `https://github.com/socketio/socket.io-client-swift.git`
   - Dependency: Up to Next Major → `16.0.0`
   - Click Add Package

4. **Add PhoneNumberKit**:
   - URL: `https://github.com/marmelroy/PhoneNumberKit.git`
   - Dependency: Up to Next Major → `3.7.0`
   - Click Add Package

**Takes 2-3 minutes to download WebRTC (~300MB)**

See `docs/SPM_DEPENDENCIES.md` for detailed package instructions

### 4. Configure Capabilities

In Xcode:
1. Select project → Target → Signing & Capabilities
2. Add Capability: "Background Modes"
   - Check: Audio, AirPlay, Picture in Picture
   - Check: Voice over IP

### 5. Update URLs

The simulator default is `http://localhost:3000` (`defaultBaseURL` in `Utilities/Constants.swift`), so usually nothing needs editing. You can override it at runtime in the app under **Settings → Server** (Save, then "Test Connection"). `signalingURL` is derived from the base URL automatically (http→ws, https→wss, same host and port).

### 6. Run!

1. Select simulator: iPhone 14 Pro
2. Press ▶️ (or ⌘R)
3. Wait for build (first time: 2-5 minutes)

## Running (After First Setup)

Every time after initial setup:

```bash
cd iOS-WebRTC-Demo/ios/WebRTCDialer
open WebRTCDialer.xcodeproj
```

Then press ▶️ in Xcode

## Testing Without Backend

To test UI without a server:

### Option 1: Mock Auth Success

Edit `Views/Authentication/PhoneNumberEntryView.swift`:

```swift
func sendVerificationCode() async {
    // Bypass server - just mark as sent
    codeSent = true
    isLoading = false
}
```

Edit `Views/Authentication/VerificationCodeView.swift`:

```swift
func verifyCode() async {
    // Accept any 6-digit code
    if code.count == 6 {
        isVerified = true
    }
}
```

### Option 2: Quick Mock Server

Create `backend/mock.js`:

```javascript
const express = require('express');
const app = express();
app.use(express.json());

app.post('/auth/send-code', (req, res) => {
    res.json({ success: true });
});

app.post('/auth/verify-code', (req, res) => {
    res.json({
        success: true,
        token: 'mock-token',
        user: { id: '123', phoneNumber: req.body.phoneNumber }
    });
});

app.listen(3000);
```

Run:
```bash
cd backend
npm init -y && npm install express
node mock.js
```

## What Works in Simulator

✅ UI and navigation
✅ Authentication screens
✅ Tab bar
✅ Keypad
✅ Settings
✅ CallKit UI (limited)

❌ VoIP pushes (need device)
❌ Real calls (need device)
❌ Camera (no camera)

## Common Issues

**"No such module 'WebRTC'"**
```bash
# Reset package caches in Xcode:
# File → Packages → Reset Package Caches
# File → Packages → Resolve Package Versions
# Clean Build Folder (Shift+⌘+K)
# Rebuild (⌘B)
```

**Build takes forever**
- First build downloads WebRTC (~15 MB)
- Can take 2-5 minutes
- Subsequent builds are faster

**"Cannot find 'WebRTCDialerApp' in scope"**
- Make sure you added all source files
- Check that `App/WebRTCDialerApp.swift` is in the project

## Testing App-to-App Calls on Two Simulators

The app places real WebRTC calls (Socket.IO signaling + `RTCPeerConnection`).
Two simulators on the same Mac can call each other against the local backend.

### 1. Start the backend

```bash
cd backend
cp .env.example .env   # first time only
# Two simulators + the smoke test share one IP, so raise the auth limiter:
echo "AUTH_RATE_LIMIT_MAX_REQUESTS=1000" >> .env
node src/index.js      # REST + signaling on http://localhost:3000
```

### 2. Point both simulators at the backend and allow the microphone

```bash
B=com.D3DigitalProductions.WebRTCDialer
for UDID in <udid-A> <udid-B>; do
  xcrun simctl boot $UDID
  xcrun simctl install $UDID <path-to>/WebRTCDialer.app
  # Only needed if the backend is not on the default http://localhost:3000
  xcrun simctl spawn $UDID defaults write $B serverBaseURL http://localhost:3000
  xcrun simctl privacy $UDID grant microphone $B
done
```

(Settings → Server in the app does the same thing interactively.)

### 3. Sign in and call

1. Sign in on each simulator with a *different, valid-looking* number, e.g.
   `(201) 555-0101` and `(201) 555-0102`. The 6-digit code is shown on screen
   (mock SMS provider) and also printed in the backend log.
2. On simulator B open **Keypad**, dial `2015550101`, tap call.
3. Simulator A shows the in-app incoming call screen; tap **Accept**.
4. Both screens show the call timer. The app console logs the state machine:

```
📡 [Signaling] → call-initiate …   📡 [Signaling] ← incoming-call …
🎧 [WebRTC] Local offer set        🎧 [WebRTC] Remote offer set
🎧 [WebRTC] ICE connection state → connected
📞 [CallManager] Call … connected (ICE connected)
🎧 [WebRTC] Stats: audio sent 0 pkts/0 B, …, transport 834 B out/1023 B in | ice=connected pc=connected
```

Launch with `xcrun simctl launch --console-pty <udid> $B` to see those logs.

### Simulator limitations (handled automatically)

| Limitation | What the app does |
|---|---|
| CallKit ends outgoing calls immediately after `CXStartCallAction` on the simulator | `CallManager.useCallKit` is `false` in simulator builds; the in-app call screens are used. On a device CallKit drives the call and the native incoming-call UI appears. |
| Starting WebRTC's voice-processing audio unit can deadlock CoreAudio and abort the process (`Initialize: RPC timeout. Apparently deadlocked`) | The audio unit stays off in the simulator, so `audio sent/received` packets are 0 while ICE/DTLS and the `transport` byte counters prove the media path. To try real audio: `xcrun simctl spawn <udid> defaults write $B simulatorAudioEnabled -bool YES` |
| No VoIP push delivery | PushKit still registers and POSTs the token to `/api/user/voip-token`; the server only logs pushes until an APNs key is configured. |

### VoIP push on a device

`ios/WebRTCDialer/WebRTCDialer.entitlements` carries `aps-environment`. It is
not wired into the build by default because the automatic "iOS Team
Provisioning Profile" does not include Push Notifications and `xcodebuild`
cannot add the capability headlessly. In Xcode, open the target's **Signing &
Capabilities** tab and add **Push Notifications** once (it registers the App ID
capability and sets `CODE_SIGN_ENTITLEMENTS`); after that PushKit delivers a
token on the device.

## Next Steps

### For Full Testing
1. Use a physical iPhone (CallKit UI and real audio need a device)
2. Set up backend server
3. Test between two devices

### See Full Guide
- [`docs/XCODE_SETUP.md`](../docs/XCODE_SETUP.md) - Detailed setup
- [`docs/HOW_IT_WORKS.md`](../docs/HOW_IT_WORKS.md) - How everything works
- [`docs/SETUP_GUIDE.md`](../docs/SETUP_GUIDE.md) - Complete setup guide

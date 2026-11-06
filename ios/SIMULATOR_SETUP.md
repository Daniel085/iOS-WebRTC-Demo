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

The target signs with `ios/WebRTCDialer/WebRTCDialer.entitlements`
(`aps-environment`), and the Push Notifications capability is registered on
the App ID (done in Xcode's Signing & Capabilities tab on 2026-11-05). On a
device the app logs `📲 [VoIP Push] Token: …` and `Token registered with
backend` right after signing in. If a device build fails with "Provisioning
profile … doesn't include the Push Notifications capability" or "PLA Update
available", accept the latest Program License Agreement at
developer.apple.com and rebuild with `-allowProvisioningUpdates`.

To make the backend actually send pushes, create an APNs auth key
(developer.apple.com → Keys → enable APNs), save the `.p8` under
`backend/certs/` (gitignored) and set in `backend/.env`:

```
APN_AUTH_METHOD=token
APN_KEY_PATH=./certs/AuthKey_<KEYID>.p8
APN_KEY_ID=<KEYID>
APN_TEAM_ID=EB25CFP6UQ
VOIP_BUNDLE_ID=com.D3DigitalProductions.WebRTCDialer.voip
```

Leave `NODE_ENV` unset for development builds (sandbox APNs). Until the key is
configured the backend logs the push instead of sending it, and callers of a
backgrounded phone get `Recipient unavailable`.

## Testing Simulator ↔ iPhone (verified 2026-11-05)

A paired iPhone calling a simulator exercises the real CallKit path: the
native incoming-call screen, `CXAnswerCallAction`, the audio-session
hand-off (`provider(didActivate:)` → `RTCAudioSession.audioSessionDidActivate`)
and real microphone audio.

```bash
# Build and install (team EB25CFP6UQ; no aps-environment entitlement, see above)
xcodebuild -project ios/WebRTCDialer.xcodeproj -scheme WebRTCDialer \
  -destination 'generic/platform=iOS' -derivedDataPath /tmp/dd build
xcrun devicectl device install app --device <udid> /tmp/dd/Build/Products/Debug-iphoneos/WebRTCDialer.app
# Launch with console output (the phone must be unlocked for this to succeed)
xcrun devicectl device process launch --console --terminate-existing --device <udid> com.D3DigitalProductions.WebRTCDialer
```

The device default server is `http://<Mac LAN IP>:3000` (Constants.swift, override
in Settings → Server); the simulator uses `http://localhost:3000`, both on the
same backend. Sign in on both, dial the phone's number from the simulator and
tap **Accept** on the phone's native call screen. Expected logs on the phone:

```
📡 [Signaling] ← incoming-call <id> from +1201555… video=false
☎️ [CallKit] Perform answer <id>
☎️ [CallKit] Audio session activated
🎧 [WebRTC] ICE connection state → connected
🎧 [WebRTC] Stats: audio sent 998 pkts/55647 B, audio received 0 pkts/0 B … ice=connected pc=connected
```

The simulator receives those packets (`audio received 997 pkts`) but sends none
(its audio unit is off, see the limitations table). Hanging up on either side
produces `call-end` → `call-ended`, both peer connections close and the phone
logs `☎️ [CallKit] Audio session deactivated`.

Gotchas on a device:

| Symptom | Cause / fix |
|---------|-------------|
| `call-error … Recipient unavailable` although the phone registered a minute ago | iOS suspended the app when the phone auto-locked or went to the background and the socket dropped (`Client disconnected … transport close` in the backend log). Without a VoIP push token the backend cannot wake it. Keep the app in the foreground and the phone unlocked (or set Auto-Lock to Never while testing). |
| `devicectl … launch` fails with "device was not, or could not be, unlocked" | Unlock the phone and retry; the install itself works while locked. |
| App shows the login screen after a relaunch | The keychain token was cleared (e.g. Logout). Sign in again; the dev code is shown on screen. |

## Next Steps

### For Full Testing
1. Use a physical iPhone (CallKit UI and real audio need a device)
2. Set up backend server
3. Test between two devices

### See Full Guide
- [`docs/XCODE_SETUP.md`](../docs/XCODE_SETUP.md) - Detailed setup
- [`docs/HOW_IT_WORKS.md`](../docs/HOW_IT_WORKS.md) - How everything works
- [`docs/SETUP_GUIDE.md`](../docs/SETUP_GUIDE.md) - Complete setup guide

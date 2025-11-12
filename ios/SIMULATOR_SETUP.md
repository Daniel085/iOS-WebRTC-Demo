# Quick Simulator Setup

**TL;DR**: Steps to run the app in Xcode Simulator

## Prerequisites

1. macOS with Xcode 14+ installed
2. CocoaPods installed: `sudo gem install cocoapods`

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

### 3. Install Dependencies

Close Xcode, then in Terminal:

```bash
cd iOS-WebRTC-Demo/ios/WebRTCDialer
pod install
```

**Important**: Takes 2-5 minutes to download WebRTC

### 4. Open Workspace

```bash
open WebRTCDialer.xcworkspace
```

⚠️ **Always open `.xcworkspace`, NEVER `.xcodeproj`**

### 5. Configure Capabilities

In Xcode:
1. Select project → Target → Signing & Capabilities
2. Add Capability: "Background Modes"
   - Check: Audio, AirPlay, Picture in Picture
   - Check: Voice over IP

### 6. Update URLs

Edit `Utilities/Constants.swift`:

```swift
enum API {
    static let baseURL = "http://localhost:3000"
    static let signalingURL = "ws://localhost:3000"
}
```

### 7. Run!

1. Select simulator: iPhone 14 Pro
2. Press ▶️ (or ⌘R)
3. Wait for build (first time: 2-5 minutes)

## Running (After First Setup)

Every time after initial setup:

```bash
cd iOS-WebRTC-Demo/ios/WebRTCDialer
open WebRTCDialer.xcworkspace
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
# Make sure you opened .xcworkspace
cd iOS-WebRTC-Demo/ios/WebRTCDialer
pod install
open WebRTCDialer.xcworkspace
```

**Build takes forever**
- First build downloads WebRTC (~15 MB)
- Can take 2-5 minutes
- Subsequent builds are faster

**"Cannot find 'WebRTCDialerApp' in scope"**
- Make sure you added all source files
- Check that `App/WebRTCDialerApp.swift` is in the project

## Next Steps

### For Full Testing
1. Use a physical iPhone (VoIP needs device)
2. Set up backend server
3. Test between two devices

### See Full Guide
- [`docs/XCODE_SETUP.md`](../docs/XCODE_SETUP.md) - Detailed setup
- [`docs/HOW_IT_WORKS.md`](../docs/HOW_IT_WORKS.md) - How everything works
- [`docs/SETUP_GUIDE.md`](../docs/SETUP_GUIDE.md) - Complete setup guide

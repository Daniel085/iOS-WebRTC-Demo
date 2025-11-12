# Setup Guide - Getting Started

This guide walks you through setting up the iOS WebRTC Dialer application from scratch.

## Prerequisites

### Required Software

- **macOS** 12.0 (Monterey) or later
- **Xcode** 14.0 or later (Xcode 15+ recommended)
- **iOS Device** (iPhone with iOS 15.0+) for testing VoIP features
- **Apple Developer Account** ($99/year) - required for VoIP capabilities
- **No additional tools required** - Swift Package Manager is built into Xcode

### Optional but Recommended

- **Git** (for version control)
- **Postman** or **curl** (for API testing)
- **Node.js** 18+ (for backend development)

## Installation Steps

### Step 1: Install Command Line Tools

```bash
# Check if Xcode command line tools are installed
xcode-select -p

# If not installed, install them
xcode-select --install
```

### Step 2: Create Xcode Project

1. **Open Xcode**
2. **Create New Project**
   - Click "Create a new Xcode project"
   - Choose "iOS" → "App"
   - Click "Next"

3. **Configure Project**
   - **Product Name**: `WebRTCDialer`
   - **Team**: Select your Apple Developer Team
   - **Organization Identifier**: `com.yourcompany` (use your reverse domain)
   - **Bundle Identifier**: Will auto-generate as `com.yourcompany.WebRTCDialer`
   - **Interface**: SwiftUI
   - **Language**: Swift
   - **Storage**: None (we'll add if needed)
   - Uncheck "Use Core Data"
   - Uncheck "Include Tests" (we'll add later)

4. **Save Project**
   - Choose location: `iOS-WebRTC-Demo/ios/`
   - Uncheck "Create Git repository" (already have one)
   - Click "Create"

### Step 3: Add Swift Package Dependencies

We use Swift Package Manager (SPM) which is built into Xcode - no additional installation needed!

In Xcode (with your project open):

1. **File → Add Package Dependencies...**

2. **Add WebRTC Package**
   - In the search box, enter: `https://github.com/stasel/WebRTC.git`
   - Dependency Rule: **Up to Next Major Version** → `114.0.0`
   - Click **Add Package**
   - Select **WebRTC** framework
   - Click **Add Package**

3. **Add Socket.IO Package**
   - File → Add Package Dependencies...
   - Enter: `https://github.com/socketio/socket.io-client-swift.git`
   - Dependency Rule: **Up to Next Major Version** → `16.0.0`
   - Click **Add Package**
   - Select **SocketIO** product
   - Click **Add Package**

4. **Add PhoneNumberKit Package**
   - File → Add Package Dependencies...
   - Enter: `https://github.com/marmelroy/PhoneNumberKit.git`
   - Dependency Rule: **Up to Next Major Version** → `3.7.0`
   - Click **Add Package**
   - Select **PhoneNumberKit** product
   - Click **Add Package**

5. **Wait for Package Resolution**
   - Xcode will download and build dependencies
   - This takes 2-3 minutes (WebRTC is ~300MB)
   - Progress shown in the top toolbar

6. **Verify Packages**
   - In Project Navigator, look for "Package Dependencies"
   - You should see: WebRTC, socket.io-client-swift, PhoneNumberKit

**For detailed SPM instructions**, see [`SPM_DEPENDENCIES.md`](./SPM_DEPENDENCIES.md)

### Step 4: Configure Project Capabilities

In Xcode:

1. **Select Project** → Select `WebRTCDialer` target
2. **Signing & Capabilities** tab

#### Add Background Modes

1. Click **"+ Capability"**
2. Search for **"Background Modes"**
3. Add it
4. Check these boxes:
   - ☑️ **Audio, AirPlay, and Picture in Picture**
   - ☑️ **Voice over IP**

#### Add Push Notifications (for VoIP)

1. Click **"+ Capability"** again
2. Search for **"Push Notifications"**
3. Add it

### Step 7: Configure Info.plist

Add required privacy descriptions:

1. Open `Info.plist`
2. Right-click → **Add Row**
3. Add these keys:

```xml
<!-- Camera Access -->
<key>NSCameraUsageDescription</key>
<string>We need access to your camera for video calls.</string>

<!-- Microphone Access -->
<key>NSMicrophoneUsageDescription</key>
<string>We need access to your microphone for voice and video calls.</string>

<!-- Contacts Access -->
<key>NSContactsUsageDescription</key>
<string>We need access to your contacts so you can easily call your friends and family.</string>

<!-- Local Network (for WebRTC) -->
<key>NSLocalNetworkUsageDescription</key>
<string>We need access to your local network to establish peer-to-peer calls.</string>

<!-- Background VoIP -->
<key>UIBackgroundModes</key>
<array>
    <string>audio</string>
    <string>voip</string>
</array>
```

**Or via Property List format** (easier to copy-paste):

| Key | Type | Value |
|-----|------|-------|
| NSCameraUsageDescription | String | We need access to your camera for video calls. |
| NSMicrophoneUsageDescription | String | We need access to your microphone for voice and video calls. |
| NSContactsUsageDescription | String | We need access to your contacts so you can easily call your friends and family. |
| NSLocalNetworkUsageDescription | String | We need access to your local network to establish peer-to-peer calls. |

### Step 8: Verify Installation

Create a simple test to verify WebRTC is imported correctly:

**Edit `ContentView.swift`:**

```swift
import SwiftUI
import WebRTC
import SocketIO
import PhoneNumberKit

struct ContentView: View {
    @State private var status = "Checking dependencies..."

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "phone.circle.fill")
                .font(.system(size: 80))
                .foregroundColor(.blue)

            Text("WebRTC Dialer")
                .font(.largeTitle)
                .bold()

            Text(status)
                .foregroundColor(.secondary)
        }
        .padding()
        .onAppear {
            checkDependencies()
        }
    }

    func checkDependencies() {
        // Test WebRTC
        RTCInitializeSSL()

        // Test PhoneNumberKit
        let phoneNumberKit = PhoneNumberKit()

        // Test Socket.IO
        let manager = SocketManager(socketURL: URL(string: "https://example.com")!)

        status = "✅ All dependencies loaded successfully!"

        // Cleanup
        RTCCleanupSSL()
    }
}
```

### Step 9: Build and Run

1. **Select a simulator** or **connect your iPhone**
2. Click **Run** (⌘R)
3. App should build and show "✅ All dependencies loaded successfully!"

**If you see build errors:**

```bash
# Clean build folder
# In Xcode: Product → Clean Build Folder (Shift + ⌘ + K)

# Reset Swift Package caches
# In Xcode: File → Packages → Reset Package Caches

# Or from terminal:
rm -rf ~/Library/Caches/org.swift.swiftpm
rm -rf ~/Library/Developer/Xcode/DerivedData
```

## Common Issues & Solutions

### Issue 1: "No such module 'WebRTC'"

**Solution:**
```bash
# In Xcode:
# 1. File → Packages → Reset Package Caches
# 2. File → Packages → Resolve Package Versions
# 3. Product → Clean Build Folder (Shift+⌘+K)
# 4. Build again (⌘B)

# Or from terminal:
rm -rf ~/Library/Caches/org.swift.swiftpm
# Then clean and rebuild in Xcode
```

### Issue 2: Package Resolution Failed

**Solution:**
```bash
# Clear SPM caches
rm -rf ~/Library/Caches/org.swift.swiftpm

# In Xcode:
# File → Packages → Reset Package Caches
# File → Packages → Update to Latest Package Versions

# If still failing, try:
rm -rf ~/Library/Developer/Xcode/DerivedData
```

### Issue 3: Build Fails with Architecture Errors

**Solution:**

In Xcode:
1. Select project → Target → Build Settings
2. Search for "Excluded Architectures"
3. Add `arm64` to "Excluded Architectures" for "Any iOS Simulator SDK"

### Issue 4: VoIP Push Not Working in Simulator

**Expected Behavior:**
- VoIP pushes **DO NOT work in iOS Simulator**
- You **MUST use a physical device** for testing VoIP features
- CallKit UI will show but pushes won't arrive

### Issue 5: "Signing for 'WebRTCDialer' requires a development team"

**Solution:**
1. Xcode → Preferences → Accounts
2. Add your Apple ID
3. Project → Signing & Capabilities → Team → Select your team

## Project Structure

After setup, your structure should look like:

```
iOS-WebRTC-Demo/
├── ios/
│   └── WebRTCDialer/
│       ├── WebRTCDialer.xcworkspace     ← OPEN THIS
│       ├── WebRTCDialer.xcodeproj       ← Don't open directly
│       ├── Podfile
│       ├── Podfile.lock
│       ├── Pods/                        ← Dependencies
│       │   ├── GoogleWebRTC/
│       │   ├── Socket.IO-Client-Swift/
│       │   └── PhoneNumberKit/
│       └── WebRTCDialer/
│           ├── WebRTCDialerApp.swift
│           ├── ContentView.swift
│           ├── Info.plist
│           └── Assets.xcassets/
├── docs/
└── README.md
```

## Next Steps

Now that your environment is set up:

1. ✅ Dependencies installed
2. ✅ Project configured
3. ✅ Capabilities enabled
4. ✅ Test build successful

**Continue to implementation:**

Follow [IMPLEMENTATION_ROADMAP.md](./IMPLEMENTATION_ROADMAP.md) - Phase 1, Week 1, Day 5 to start building the actual app structure.

## Dependency Details

### GoogleWebRTC (~15 MB)

**What it provides:**
- `RTCPeerConnection` - Core WebRTC connection
- `RTCDataChannel` - Data channel for signaling
- `RTCVideoTrack` / `RTCAudioTrack` - Media tracks
- `RTCVideoView` - Video rendering
- Hardware acceleration for H.264/VP8

**Version**: 1.1.31999 (corresponds to WebRTC M99)

### Socket.IO-Client-Swift (~2 MB)

**What it provides:**
- WebSocket client
- Automatic reconnection
- Event-based messaging
- Binary support

**Version**: 16.0.1

### PhoneNumberKit (~1 MB)

**What it provides:**
- Phone number parsing
- E.164 formatting
- Country code detection
- Number validation

**Version**: 3.7.4

## Development Tools

### Recommended Xcode Extensions

- **SwiftLint** - Code quality
- **SourceKit-LSP** - Better autocomplete

### Debug Tools

```bash
# View CocoaPods installation
pod list

# Check pod versions
pod outdated

# Update specific pod
pod update GoogleWebRTC
```

### Testing on Device

For VoIP features, you need:

1. **Physical iPhone** (iOS 15.0+)
2. **Developer Certificate** (free or paid)
3. **VoIP Entitlements** (requires paid developer account)

To test without paid account:
- Basic WebRTC calls work
- CallKit UI works
- VoIP pushes **will NOT work**

## Resources

- [WebRTC iOS Documentation](https://webrtc.github.io/webrtc-org/native-code/ios/)
- [CallKit Documentation](https://developer.apple.com/documentation/callkit)
- [PushKit Documentation](https://developer.apple.com/documentation/pushkit)
- [CocoaPods Guides](https://guides.cocoapods.org/)

## Troubleshooting Commands

```bash
# Check Ruby version (for CocoaPods)
ruby --version

# Check CocoaPods version
pod --version

# Update CocoaPods
sudo gem install cocoapods

# Clear CocoaPods cache
pod cache clean --all

# Reinstall all pods
rm -rf Pods/ Podfile.lock
pod install

# Reset Xcode derived data
rm -rf ~/Library/Developer/Xcode/DerivedData
```

## Ready to Build!

Your development environment is now ready. Proceed to building the app by following the Implementation Roadmap, starting with creating the core services and views.

🚀 **Let's build an amazing iOS VoIP app!**

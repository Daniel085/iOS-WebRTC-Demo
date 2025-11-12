# Setting Up the Xcode Project

This guide walks you through creating and running the iOS WebRTC Dialer app in Xcode.

## Prerequisites

- macOS 12.0 or later
- Xcode 14.0 or later
- CocoaPods installed (`sudo gem install cocoapods`)

## Step-by-Step Setup

### Step 1: Create the Xcode Project

Since we have the source code but not the `.xcodeproj` file, we need to create it:

1. **Open Xcode**
   - Launch Xcode from Applications

2. **Create New Project**
   - Click "Create a new Xcode project"
   - Or: File → New → Project

3. **Choose Template**
   - Select **iOS** tab at the top
   - Choose **App** under "Application"
   - Click **Next**

4. **Configure Project**
   ```
   Product Name: WebRTCDialer
   Team: Select your team (or leave as "None" for simulator)
   Organization Identifier: com.yourcompany (or your reverse domain)
   Bundle Identifier: Will auto-generate (e.g., com.yourcompany.WebRTCDialer)
   Interface: SwiftUI
   Language: Swift
   Storage: None
   ☐ Use Core Data (leave unchecked)
   ☐ Include Tests (leave unchecked for now)
   ```
   - Click **Next**

5. **Save Location**
   - Navigate to: `iOS-WebRTC-Demo/ios/`
   - **IMPORTANT**: If `WebRTCDialer` folder exists, delete it first!
   - Save as: `WebRTCDialer`
   - ☐ Create Git repository (leave unchecked - we already have one)
   - Click **Create**

### Step 2: Replace Default Files

Xcode created some default files. We need to replace them with our code:

1. **Delete Default Files**
   - In Xcode's Project Navigator (left sidebar)
   - Select these files and delete (Move to Trash):
     - `ContentView.swift`
     - `WebRTCDialerApp.swift`
     - `Assets.xcassets` (we'll recreate it)

2. **Add Our Source Code**

   **Option A: Drag and Drop (Easiest)**
   - In Finder, open: `iOS-WebRTC-Demo/ios/WebRTCDialer/WebRTCDialer/`
   - Drag these folders into Xcode's Project Navigator:
     - `App/`
     - `Models/`
     - `Views/`
     - `Services/`
     - `Utilities/`
   - When prompted:
     - ☑️ Copy items if needed
     - ☑️ Create groups
     - ☑️ Add to target: WebRTCDialer
   - Click **Finish**

   **Option B: Add Files Manually**
   - Right-click on `WebRTCDialer` folder in Project Navigator
   - Choose "Add Files to 'WebRTCDialer'..."
   - Navigate to `iOS-WebRTC-Demo/ios/WebRTCDialer/WebRTCDialer/`
   - Select folders: `App`, `Models`, `Views`, `Services`, `Utilities`
   - ☑️ Copy items if needed
   - ☑️ Create groups
   - ☑️ Add to target: WebRTCDialer
   - Click **Add**

3. **Replace Info.plist**
   - Copy our `Info.plist` to replace Xcode's default
   - Or add the privacy keys manually (see Info.plist section below)

4. **Create Assets Catalog**
   - Right-click on `WebRTCDialer` folder
   - New File → Resource → Asset Catalog
   - Name it `Assets`
   - Click **Create**

### Step 3: Copy Podfile

1. **Copy Podfile to Project Root**
   ```bash
   # In Terminal
   cd ~/iOS-WebRTC-Demo/ios/WebRTCDialer

   # Podfile should already be here from our setup
   # If not, copy it from the repo
   ```

2. **Verify Podfile Contents**
   ```ruby
   platform :ios, '15.0'
   use_frameworks!

   target 'WebRTCDialer' do
     pod 'GoogleWebRTC', '~> 1.1.31999'
     pod 'Socket.IO-Client-Swift', '~> 16.0.1'
     pod 'PhoneNumberKit', '~> 3.7.4'
   end

   post_install do |installer|
     installer.pods_project.targets.each do |target|
       target.build_configurations.each do |config|
         config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '15.0'
         config.build_settings['ENABLE_BITCODE'] = 'NO'
       end
     end
   end
   ```

### Step 4: Install CocoaPods Dependencies

1. **Close Xcode** (Important!)
   - Xcode → Quit Xcode (⌘Q)

2. **Install Pods**
   ```bash
   cd ~/iOS-WebRTC-Demo/ios/WebRTCDialer
   pod install
   ```

   You should see:
   ```
   Analyzing dependencies
   Downloading dependencies
   Installing GoogleWebRTC (1.1.31999)
   Installing PhoneNumberKit (3.7.4)
   Installing Socket.IO-Client-Swift (16.0.1)
   Generating Pods project
   Integrating client project

   [!] Please close any current Xcode sessions and use
   `WebRTCDialer.xcworkspace` for this project from now on.

   Pod installation complete! There are 3 dependencies from the Podfile.
   ```

   **This creates:**
   - `Pods/` folder with dependencies
   - `WebRTCDialer.xcworkspace` ← **Open this from now on!**
   - `Podfile.lock`

### Step 5: Open Workspace

**CRITICAL**: Always open the `.xcworkspace`, NOT the `.xcodeproj`!

```bash
cd ~/iOS-WebRTC-Demo/ios/WebRTCDialer
open WebRTCDialer.xcworkspace
```

Or double-click `WebRTCDialer.xcworkspace` in Finder.

### Step 6: Configure Project Settings

1. **Select Project**
   - Click on `WebRTCDialer` (blue icon) in Project Navigator

2. **General Tab**
   - **Identity**
     - Display Name: `WebRTC Dialer`
     - Bundle Identifier: `com.yourcompany.webrtcdialer`

   - **Deployment Info**
     - Minimum Deployments: iOS 15.0
     - ☑️ iPhone
     - ☐ iPad (optional, leave unchecked for now)
     - Device Orientation: ☑️ Portrait (uncheck others for now)

3. **Signing & Capabilities Tab**

   **A. Signing**
   - Team: Select your Apple Developer team
     - If you don't have one: Select "None" (simulator only)
   - ☑️ Automatically manage signing

   **B. Add Capabilities**

   Click **+ Capability** button:

   **Add "Background Modes"**
   - Search: "Background Modes"
   - Add it
   - Check these boxes:
     - ☑️ Audio, AirPlay, and Picture in Picture
     - ☑️ Voice over IP

   **Add "Push Notifications"** (optional for simulator)
   - Search: "Push Notifications"
   - Add it

4. **Build Settings Tab**
   - Search for: "Bitcode"
   - Set **Enable Bitcode** to **No**

### Step 7: Configure Info.plist

1. **Open Info.plist**
   - Click on `Info.plist` in Project Navigator

2. **Add Privacy Permissions**

   Right-click → Add Row, then add these keys:

   | Key | Type | Value |
   |-----|------|-------|
   | Privacy - Camera Usage Description | String | We need access to your camera for video calls. |
   | Privacy - Microphone Usage Description | String | We need access to your microphone for voice and video calls. |
   | Privacy - Contacts Usage Description | String | We need access to your contacts so you can easily call your friends and family. |
   | Privacy - Local Network Usage Description | String | We need access to your local network to establish peer-to-peer calls. |

3. **Add Required Background Modes**

   Add this key (if not already present):

   | Key | Type |
   |-----|------|
   | Required background modes | Array |

   Add items to the array:
   - Item 0: `audio` (String)
   - Item 1: `voip` (String)

### Step 8: Update Constants

1. **Open `Utilities/Constants.swift`**

2. **Update API URLs**
   ```swift
   enum API {
       // For testing with simulator, use localhost
       static let baseURL = "http://localhost:3000"
       static let signalingURL = "ws://localhost:3000"

       // For device testing with local backend:
       // static let baseURL = "http://YOUR_IP:3000"
       // static let signalingURL = "ws://YOUR_IP:3000"
   }
   ```

3. **Update Bundle ID** (if different)
   ```swift
   enum VoIP {
       static let bundleID = "com.yourcompany.webrtcdialer"
   }
   ```

### Step 9: Build the Project

1. **Select Simulator**
   - At the top of Xcode window
   - Click on the device selector (next to the app name)
   - Choose: **iPhone 14 Pro** (or any iOS 15+ simulator)

2. **Build**
   - Click the Play button (▶️) or press ⌘R
   - Or: Product → Run

3. **First Build Takes Time**
   - WebRTC is a large library (~15 MB)
   - First build may take 2-5 minutes
   - Subsequent builds will be faster

### Step 10: Fix Common Build Errors

If you encounter errors:

**Error: "No such module 'WebRTC'"**
```
Solution:
1. Make sure you opened .xcworkspace (not .xcodeproj)
2. Clean build folder: Product → Clean Build Folder (Shift+⌘+K)
3. Quit Xcode and run: pod deintegrate && pod install
4. Reopen .xcworkspace
```

**Error: "Command PhaseScriptExecution failed"**
```
Solution:
1. Build Settings → Enable Bitcode → Set to "No"
2. Clean and rebuild
```

**Error: Missing file 'WebRTCDialerApp.swift'**
```
Solution:
1. Make sure you added all source files from Step 2
2. Check that App/WebRTCDialerApp.swift is in the project
3. Right-click → Show in Project Navigator to verify
```

**Error: Framework not found**
```
Solution:
1. cd ios/WebRTCDialer
2. pod install
3. Clean build folder in Xcode
4. Rebuild
```

## Running in Simulator

### What Works in Simulator

✅ **Works:**
- App UI and navigation
- Authentication flow UI (phone entry, code entry)
- Tab bar navigation
- Keypad interface
- Settings screen
- WebRTC initialization
- CallKit UI (limited)

❌ **Doesn't Work:**
- **VoIP Push Notifications** (requires physical device)
- **Real phone calls** (need physical device + backend)
- **Camera** (simulator has no camera)
- **Microphone** (limited)
- **Actual WebRTC media** (need two devices or one device + web)

### Testing Without Backend

If you don't have the backend server running yet:

**Option 1: Test UI Only**
```swift
// In PhoneNumberEntryView.swift
// Temporarily bypass server call:

func sendVerificationCode() async {
    // Comment out the real call:
    // try await AuthenticationService.shared
    //     .sendVerificationCode(phoneNumber: phoneNumber)

    // Fake success:
    codeSent = true
}
```

**Option 2: Mock Authentication**
```swift
// In VerificationCodeView.swift
// Accept any code:

func verifyCode() async {
    // Accept any 6-digit code
    if code.count == 6 {
        isVerified = true
        appState.login()
    }
}
```

**Option 3: Start Authenticated**
```swift
// In WebRTCDialerApp.swift
// Start logged in:

init() {
    // Fake a token
    KeychainHelper.save(key: "authToken", data: "fake-token-for-testing")
}
```

### Testing With Mock Backend

Create a simple local server for testing:

**File: `backend/mock-server.js`**
```javascript
const express = require('express');
const app = express();

app.use(express.json());

// Mock send code
app.post('/auth/send-code', (req, res) => {
    console.log('Send code to:', req.body.phoneNumber);
    res.json({ success: true });
});

// Mock verify code - accept any code
app.post('/auth/verify-code', (req, res) => {
    console.log('Verify code:', req.body);
    res.json({
        success: true,
        token: 'mock-jwt-token-' + Date.now(),
        user: {
            id: 'user-123',
            phoneNumber: req.body.phoneNumber
        }
    });
});

app.listen(3000, () => {
    console.log('Mock server running on http://localhost:3000');
});
```

Run it:
```bash
cd backend
npm init -y
npm install express
node mock-server.js
```

## Debugging in Xcode

### Viewing Console Output

- Show Debug Area: View → Debug Area → Show Debug Area (⌘⇧Y)
- Console is at the bottom
- You'll see `print()` statements here

### Breakpoints

- Click on line number to add breakpoint
- Run app
- When breakpoint hits, inspect variables in Debug Area

### Viewing UI Hierarchy

- Debug → View Debugging → Capture View Hierarchy
- 3D view of all UI elements

### Common Debug Messages

```
✅ Good:
"VoIP token: abc123..."  → VoIP registered
"Connected to signaling server" → Backend connected
"WebRTC initialized" → WebRTC ready

⚠️  Warnings:
"Failed to connect to server" → Backend not running
"Invalid URL" → Check Constants.swift
"VoIP push not available" → Normal in simulator

❌ Errors:
"No such module 'WebRTC'" → Pod install issue
"Thread 1: signal SIGABRT" → Crash, check console
```

## Simulator Limitations

### CallKit in Simulator

CallKit **does work** in simulator, but:
- Shows native call UI
- Can test call flow
- **But**: No actual audio/video
- **But**: No VoIP pushes

### Testing CallKit

1. Run app in simulator
2. Go to Keypad
3. Enter a phone number
4. Tap call button
5. You should see CallKit outgoing call UI
6. Tap End to dismiss

### WebRTC in Simulator

WebRTC initializes but:
- No camera available
- Microphone limited
- Can't test actual calls between two simulators easily

## Next Steps

### For Full Testing

1. **Physical Device**
   - Connect iPhone via USB
   - Select it in device selector
   - Run app on device
   - Test VoIP pushes, real calls

2. **Backend Server**
   - Set up Node.js backend
   - Deploy to server or run locally
   - Update Constants.swift with IP/URL

3. **Two Devices**
   - Install on two iPhones
   - Make actual calls between them

### Recommended Testing Flow

```
Phase 1: Simulator UI Testing
├── Test authentication flow
├── Test tab navigation
├── Test keypad interface
└── Test settings screen

Phase 2: Simulator + Mock Backend
├── Test API calls
├── Test authentication with mock server
└── Test WebRTC initialization

Phase 3: One Physical Device + Web
├── Test VoIP pushes
├── Test CallKit on device
├── Test camera/microphone
└── Test WebRTC with web peer

Phase 4: Two Physical Devices
├── Full end-to-end call test
├── Test video calls
├── Test all features
└── Production testing
```

## Quick Start Commands

```bash
# 1. Navigate to project
cd ~/iOS-WebRTC-Demo/ios/WebRTCDialer

# 2. Install dependencies
pod install

# 3. Open workspace
open WebRTCDialer.xcworkspace

# 4. In Xcode:
#    - Select simulator (iPhone 14 Pro)
#    - Press ⌘R to run

# 5. If you want a mock backend:
cd ../../backend
npm init -y && npm install express
# Create mock-server.js (see above)
node mock-server.js
```

## Troubleshooting Checklist

Before asking for help, verify:

- [ ] Opened `.xcworkspace` (NOT `.xcodeproj`)
- [ ] Ran `pod install` successfully
- [ ] All source files added to project
- [ ] Build target is iOS 15.0+
- [ ] Simulator is iOS 15.0+
- [ ] Enable Bitcode is set to "No"
- [ ] Info.plist has privacy descriptions
- [ ] Constants.swift has valid URLs
- [ ] Clean build folder tried (Shift+⌘+K)

## Success!

If the build succeeds, you should see:
- App launches in simulator
- Phone number entry screen appears
- Can navigate through UI

**Congratulations! The app is running!** 🎉

For actual call testing, you'll need:
1. Physical iOS device (for VoIP)
2. Backend server running
3. Optionally: Second device to call

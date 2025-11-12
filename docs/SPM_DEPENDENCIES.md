# Swift Package Manager Dependencies

This project uses Swift Package Manager for dependency management. No additional tools like CocoaPods needed!

## Adding Dependencies to Your Xcode Project

### Step 1: Open Project in Xcode

```bash
cd ios/WebRTCDialer
open WebRTCDialer.xcodeproj  # Note: .xcodeproj, not .xcworkspace
```

### Step 2: Add Package Dependencies

1. In Xcode, select your project in the navigator
2. Select the "WebRTCDialer" target
3. Go to the "Package Dependencies" tab
4. Click the "+" button to add packages

### Required Packages

Add these three packages in the following order:

#### 1. WebRTC
- **URL**: `https://github.com/stasel/WebRTC.git`
- **Version**: Up to Next Major Version `114.0.0`
- **What it provides**: Google WebRTC framework (audio/video calling)

#### 2. Socket.IO Client Swift
- **URL**: `https://github.com/socketio/socket.io-client-swift.git`
- **Version**: Up to Next Major Version `16.0.0`
- **What it provides**: WebSocket communication with signaling server

#### 3. PhoneNumberKit
- **URL**: `https://github.com/marmelroy/PhoneNumberKit.git`
- **Version**: Up to Next Major Version `3.7.0`
- **What it provides**: Phone number validation and formatting

### Step 3: Configure Package Dependencies

For each package:
1. Paste the URL
2. Choose "Up to Next Major Version"
3. Click "Add Package"
4. Select the appropriate product (usually default is correct)
5. Click "Add Package" again to confirm

### Step 4: Import in Your Code

The packages are now available to import:

```swift
import WebRTC
import SocketIO
import PhoneNumberKit
```

## Manual Configuration (Alternative)

If you prefer to add packages manually, create/edit `Package.swift` in your project:

```swift
// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "WebRTCDialer",
    platforms: [
        .iOS(.v15)
    ],
    products: [
        .library(
            name: "WebRTCDialer",
            targets: ["WebRTCDialer"])
    ],
    dependencies: [
        .package(url: "https://github.com/stasel/WebRTC.git", from: "114.0.0"),
        .package(url: "https://github.com/socketio/socket.io-client-swift.git", from: "16.0.1"),
        .package(url: "https://github.com/marmelroy/PhoneNumberKit.git", from: "3.7.4")
    ],
    targets: [
        .target(
            name: "WebRTCDialer",
            dependencies: [
                .product(name: "WebRTC", package: "WebRTC"),
                .product(name: "SocketIO", package: "socket.io-client-swift"),
                .product(name: "PhoneNumberKit", package: "PhoneNumberKit")
            ]
        )
    ]
)
```

## Dependency Details

### WebRTC (stasel/WebRTC)
- Pre-built XCFramework of Google WebRTC
- Includes both simulator and device binaries
- Same binaries as the CocoaPods GoogleWebRTC pod
- Size: ~300MB (includes debug symbols)
- Supports: iOS 12+, arm64 + x86_64

**Why this version?**
The official GoogleWebRTC doesn't provide SPM support. This community package wraps the same official binaries in SPM format.

### Socket.IO Client Swift
- Official Socket.IO client for Swift
- WebSocket and HTTP long-polling support
- Automatic reconnection
- Supports: iOS 13+

### PhoneNumberKit
- Phone number parsing and validation
- Formatting for any locale
- E.164 format support
- Based on Google's libphonenumber
- Supports: iOS 12+

## Advantages Over CocoaPods

✅ **No external tool required** - SPM is built into Xcode
✅ **Faster setup** - No `pod install` needed
✅ **Better Xcode integration** - Native dependency resolution
✅ **Easier CI/CD** - No additional installation steps
✅ **Smaller repo** - No Pods/ directory or .xcworkspace
✅ **Cleaner project** - Just .xcodeproj file

## Updating Dependencies

### In Xcode:
1. File → Packages → Update to Latest Package Versions

### Via Command Line:
```bash
xcodebuild -resolvePackageDependencies
```

## Troubleshooting

### "Package Resolution Failed"

**Solution 1: Reset Package Cache**
```bash
rm -rf ~/Library/Caches/org.swift.swiftpm
rm -rf ~/Library/Developer/Xcode/DerivedData
```

**Solution 2: In Xcode**
- File → Packages → Reset Package Caches
- File → Packages → Resolve Package Versions

### "WebRTC Framework Not Found"

Make sure the WebRTC package was added correctly:
1. Project navigator → Select project
2. Package Dependencies tab
3. Verify "WebRTC" is listed
4. Clean build folder (Cmd+Shift+K)
5. Rebuild (Cmd+B)

### "Module 'WebRTC' not found"

Ensure the WebRTC framework is linked:
1. Select target → General tab
2. Frameworks, Libraries, and Embedded Content
3. WebRTC should be listed
4. If not, add it via "+" button

### Xcode Version Requirements

- **Minimum Xcode**: 13.0
- **Recommended**: Xcode 15.0+
- SPM support improves with each Xcode version

## Migration from CocoaPods

If you previously used CocoaPods:

1. **Close Xcode**
2. **Delete CocoaPods files**:
   ```bash
   cd ios/WebRTCDialer
   rm -rf Pods/
   rm Podfile
   rm Podfile.lock
   rm -rf WebRTCDialer.xcworkspace
   ```
3. **Open .xcodeproj** (not .xcworkspace)
4. **Add SPM packages** as described above
5. **Clean build folder**: Cmd+Shift+K
6. **Build**: Cmd+B

## CI/CD Integration

### GitHub Actions

```yaml
- name: Resolve Swift Package Dependencies
  run: |
    cd ios/WebRTCDialer
    xcodebuild -resolvePackageDependencies -project WebRTCDialer.xcodeproj

- name: Build
  run: |
    cd ios/WebRTCDialer
    xcodebuild -project WebRTCDialer.xcodeproj \
               -scheme WebRTCDialer \
               -sdk iphonesimulator \
               -destination 'platform=iOS Simulator,name=iPhone 15'
```

### Fastlane

```ruby
lane :resolve_dependencies do
  sh "xcodebuild -resolvePackageDependencies"
end
```

## Version Pinning

For reproducible builds, you can pin exact versions in Xcode:

1. Select project → Package Dependencies
2. Right-click package → "Use Exact Version"
3. Specify exact version (e.g., `114.5678.0`)

Or in Package.swift:
```swift
.package(url: "...", exact: "114.5678.0")
```

## Offline Development

SPM caches packages locally. After initial download, you can work offline.

Cache location:
```bash
~/Library/Caches/org.swift.swiftpm/
```

## Resources

- [Apple SPM Documentation](https://developer.apple.com/documentation/swift_packages)
- [WebRTC SPM Package](https://github.com/stasel/WebRTC)
- [Socket.IO Swift Client](https://github.com/socketio/socket.io-client-swift)
- [PhoneNumberKit](https://github.com/marmelroy/PhoneNumberKit)

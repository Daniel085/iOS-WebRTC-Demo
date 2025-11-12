# WebRTCDialer iOS Application

This is the iOS application for the WebRTC Dialer project.

## Project Structure

```
WebRTCDialer/
├── WebRTCDialer.xcodeproj           # Xcode project
├── WebRTCDialer/
│   ├── App/
│   │   └── WebRTCDialerApp.swift   # App entry point
│   │
│   ├── Models/
│   │   ├── Call.swift              # Call data model
│   │   ├── Contact.swift           # Contact data model
│   │   └── User.swift              # User and auth models
│   │
│   ├── Views/
│   │   ├── Authentication/
│   │   │   ├── AuthenticationView.swift
│   │   │   ├── PhoneNumberEntryView.swift
│   │   │   └── VerificationCodeView.swift
│   │   │
│   │   ├── Main/
│   │   │   ├── MainTabView.swift
│   │   │   ├── RecentsView.swift
│   │   │   ├── ContactsView.swift
│   │   │   ├── KeypadView.swift
│   │   │   └── SettingsView.swift
│   │   │
│   │   └── Call/
│   │       └── (To be implemented)
│   │
│   ├── Services/
│   │   ├── Authentication/
│   │   │   └── AuthenticationService.swift
│   │   ├── CallKit/
│   │   │   └── (To be implemented)
│   │   ├── WebRTC/
│   │   │   └── (To be implemented)
│   │   ├── Signaling/
│   │   │   └── (To be implemented)
│   │   └── VoIP/
│   │       └── (To be implemented)
│   │
│   ├── Utilities/
│   │   ├── KeychainHelper.swift    # Secure storage
│   │   └── Constants.swift         # App constants
│   │
│   ├── Resources/
│   │   └── (Assets and resources)
│   │
│   └── Info.plist                  # App configuration
```

## Current Status

### ✅ Completed
- Basic project structure
- Authentication UI (Phone number entry + verification code)
- Main tab bar navigation
- Basic views (Recents, Contacts, Keypad, Settings)
- Authentication service foundation
- Secure keychain storage
- Models for Call, Contact, User

### 🚧 In Progress
- WebRTC integration
- CallKit integration
- VoIP push notifications
- Contacts framework integration

### 📋 To Do
- Signaling client (WebSocket)
- Active call screens
- Video call UI
- Call history
- Contact integration

## Dependencies

The project uses Swift Package Manager (built into Xcode):

- **WebRTC** (~300 MB) - WebRTC library for voice/video calling
  - Package: `https://github.com/stasel/WebRTC.git`
- **Socket.IO-Client-Swift** (~2 MB) - WebSocket client for signaling
  - Package: `https://github.com/socketio/socket.io-client-swift.git`
- **PhoneNumberKit** (~1 MB) - Phone number parsing and validation
  - Package: `https://github.com/marmelroy/PhoneNumberKit.git`

## Setup Instructions

### Prerequisites
- macOS 12.0+
- Xcode 14.0+ (Xcode 15+ recommended)
- Apple Developer Account (for VoIP features)
- **No additional tools required** - Swift Package Manager is built into Xcode

### Installation

1. **Open Project**:
   ```bash
   cd ios/WebRTCDialer
   open WebRTCDialer.xcodeproj
   ```

2. **Add Swift Package Dependencies**:
   - In Xcode: File → Add Package Dependencies
   - Add these packages:
     - WebRTC: `https://github.com/stasel/WebRTC.git` (v114.0.0+)
     - Socket.IO: `https://github.com/socketio/socket.io-client-swift.git` (v16.0.0+)
     - PhoneNumberKit: `https://github.com/marmelroy/PhoneNumberKit.git` (v3.7.0+)
   - Wait for package resolution (2-3 minutes)
   - See `../docs/SPM_DEPENDENCIES.md` for detailed instructions

3. **Configure Signing**:
   - Select the WebRTCDialer target
   - Go to Signing & Capabilities
   - Select your development team

5. **Update Constants**:
   - Open `Utilities/Constants.swift`
   - Update `API.baseURL` with your backend URL
   - Update `API.signalingURL` with your WebSocket URL
   - Update `ICE.turnServer` credentials (if you have a TURN server)
   - Update `VoIP.bundleID` with your bundle identifier

### Running the App

1. Select a simulator or connect your iPhone
2. Click Run (⌘R)
3. The app should build and launch

**Note**: VoIP push notifications require a physical device and won't work in the simulator.

## Configuration

### Info.plist

The following privacy permissions are configured:

- **Camera**: For video calls
- **Microphone**: For voice and video calls
- **Contacts**: To display user's contacts
- **Local Network**: For WebRTC peer connections

Background modes enabled:
- Audio (for calls in background)
- VoIP (for receiving calls when app is terminated)

### Capabilities

Enable these in Xcode → Target → Signing & Capabilities:

1. **Background Modes**
   - Audio, AirPlay, and Picture in Picture
   - Voice over IP

2. **Push Notifications**
   - Required for VoIP pushes

## Key Features

### Authentication Flow
- Phone number entry with validation
- SMS verification code (6-digit)
- Secure token storage in Keychain
- Automatic session persistence

### Main Interface
- **Recents**: Call history
- **Contacts**: Address book integration
- **Keypad**: Manual dialing
- **Settings**: User preferences and sign out

### Security
- Tokens stored in Keychain
- HTTPS/WSS for all network communication
- No sensitive data in UserDefaults
- Secure authentication flow

## Development

### Adding New Features

1. **Models**: Add to `Models/` folder
2. **Views**: Add to appropriate `Views/` subfolder
3. **Services**: Add to appropriate `Services/` subfolder
4. **Utilities**: Add helpers to `Utilities/`

### Code Style

- Use SwiftUI for all new views
- Follow MVVM pattern (ViewModel for business logic)
- Use `async/await` for asynchronous operations
- Document complex functions with comments

### Testing

To test the app:

1. **Authentication**: Currently points to `Constants.API.baseURL` - update with your server
2. **VoIP**: Requires physical device and proper APNs setup
3. **CallKit**: Works on device, limited in simulator
4. **WebRTC**: Best tested between two physical devices

## Troubleshooting

### Build Errors

**"No such module 'WebRTC'"**
```bash
# Reinstall pods
pod deintegrate
pod install
```

**Pod install takes forever**
```bash
pod install --repo-update
```

### Runtime Issues

**Can't connect to server**
- Check `Constants.swift` has correct URLs
- Verify backend is running
- Check network connectivity

**VoIP push not working**
- VoIP requires physical device
- Check APNs certificates are configured
- Verify bundle ID matches

## Next Steps

Follow the implementation roadmap to continue development:

1. **WebRTC Client** (`Services/WebRTC/WebRTCClient.swift`)
2. **CallKit Manager** (`Services/CallKit/CallKitManager.swift`)
3. **VoIP Push Manager** (`Services/VoIP/VoIPPushManager.swift`)
4. **Signaling Client** (`Services/Signaling/SignalingClient.swift`)
5. **Call Screens** (`Views/Call/`)

See `/docs/IMPLEMENTATION_ROADMAP.md` for detailed steps.

## Resources

- [Setup Guide](../../docs/SETUP_GUIDE.md)
- [WebRTC Integration](../../docs/WEBRTC_INTEGRATION.md)
- [CallKit Integration](../../docs/CALLKIT_INTEGRATION.md)
- [Implementation Roadmap](../../docs/IMPLEMENTATION_ROADMAP.md)

## License

[Your License Here]

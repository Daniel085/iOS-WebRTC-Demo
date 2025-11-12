# UI/UX Flow and Screen Designs

## Overview

This document outlines the user interface and user experience flow for the iOS WebRTC dialer application. The goal is to create a native, intuitive experience that feels like the iOS Phone app.

## App Structure

```
├── Authentication Flow
│   ├── Phone Number Entry
│   └── Verification Code
│
├── Main Tab Bar
│   ├── Favorites (Optional)
│   ├── Recents
│   ├── Contacts
│   ├── Keypad
│   └── Settings
│
├── Call Screens
│   ├── Outgoing Call
│   ├── Incoming Call (CallKit)
│   ├── Active Audio Call
│   └── Active Video Call
│
└── Settings
    ├── Profile
    ├── Notifications
    └── About
```

## Screen Flows

### 1. Authentication Flow

#### Screen 1: Phone Number Entry
```
┌─────────────────────────────────┐
│  ←                              │
│                                 │
│        📱                       │
│                                 │
│   Enter Your Phone Number      │
│                                 │
│  We'll send you a verification │
│  code to confirm your number   │
│                                 │
│  ┌───────────────────────────┐ │
│  │ +1 (555) 123-4567         │ │
│  └───────────────────────────┘ │
│                                 │
│  ┌───────────────────────────┐ │
│  │      Send Code            │ │
│  └───────────────────────────┘ │
│                                 │
└─────────────────────────────────┘
```

**Interactions:**
- Auto-format phone number as user types
- Enable/disable "Send Code" based on validity
- Show loading state when sending
- Display error messages inline

#### Screen 2: Verification Code
```
┌─────────────────────────────────┐
│  ←                              │
│                                 │
│        ✉️                       │
│                                 │
│   Enter Verification Code      │
│                                 │
│      Sent to +1 555-123-4567   │
│                                 │
│  ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐      │
│  │1│ │2│ │3│ │4│ │5│ │6│      │
│  └─┘ └─┘ └─┘ └─┘ └─┘ └─┘      │
│                                 │
│  ┌───────────────────────────┐ │
│  │        Verify             │ │
│  └───────────────────────────┘ │
│                                 │
│      Didn't receive code?      │
│         Resend Code            │
│                                 │
└─────────────────────────────────┘
```

**Interactions:**
- Auto-focus on code input
- Auto-submit when 6 digits entered
- Resend code with countdown timer (60s)
- Clear error on new input

### 2. Main App - Tab Bar

#### Tab 1: Recents
```
┌─────────────────────────────────┐
│  Recents              Edit      │
│                                 │
│  All    Missed                  │
│                                 │
│  ○ John Doe              📞 ⓘ  │
│  +1 555-123-4567                │
│  Today, 2:30 PM                 │
│  ────────────────────────────  │
│  📞 Jane Smith           📞 ⓘ  │
│  +1 555-987-6543                │
│  Today, 1:15 PM                 │
│  ────────────────────────────  │
│  ⚠️ Mike Johnson         📞 ⓘ  │
│  (Mobile) Missed Call           │
│  Yesterday, 4:45 PM             │
│  ────────────────────────────  │
│                                 │
│ [Favorites] [Recents] [Contacts]│
│      [Keypad]    [Settings]     │
└─────────────────────────────────┘
```

**Features:**
- Segmented control: All / Missed
- Icons indicate call direction (outgoing/incoming/missed)
- Tap row to view details
- Tap phone icon to call back
- Tap info icon for contact details
- Swipe to delete
- Video call icon if it was video

#### Tab 2: Contacts
```
┌─────────────────────────────────┐
│  Contacts             + ⚙️      │
│                                 │
│  🔍 Search                      │
│                                 │
│  ────── A ──────                │
│  👤 Alex Anderson        📞 📹  │
│  +1 555-111-2222                │
│  ────────────────────────────  │
│  👤 Amy Adams            📞 📹  │
│  +1 555-333-4444                │
│  ────────────────────────────  │
│  ────── B ──────                │
│  👤 Bob Brown            📞 📹  │
│  +1 555-555-6666                │
│  ────────────────────────────  │
│                                 │
│ [Favorites] [Recents] [Contacts]│
│      [Keypad]    [Settings]     │
└─────────────────────────────────┘
```

**Features:**
- Search bar at top
- Alphabetical sections with index
- Contact photo or initials
- Quick call buttons (voice/video)
- Pull to refresh
- Fast scroll using alphabet index

#### Tab 3: Keypad
```
┌─────────────────────────────────┐
│                                 │
│                                 │
│    +1 555-123-4567              │
│    ________________             │
│                                 │
│                                 │
│    ┌───┐  ┌───┐  ┌───┐         │
│    │ 1 │  │ 2 │  │ 3 │         │
│    │   │  │ABC│  │DEF│         │
│    └───┘  └───┘  └───┘         │
│    ┌───┐  ┌───┐  ┌───┐         │
│    │ 4 │  │ 5 │  │ 6 │         │
│    │GHI│  │JKL│  │MNO│         │
│    └───┘  └───┘  └───┘         │
│    ┌───┐  ┌───┐  ┌───┐         │
│    │ 7 │  │ 8 │  │ 9 │         │
│    │PQRS│ │TUV│  │WXYZ│        │
│    └───┘  └───┘  └───┘         │
│    ┌───┐  ┌───┐  ┌───┐         │
│    │ * │  │ 0 │  │ # │         │
│    │   │  │ + │  │   │         │
│    └───┘  └───┘  └───┘         │
│                                 │
│        🎥     📞     ⌫          │
│                                 │
│ [Favorites] [Recents] [Contacts]│
│      [Keypad]    [Settings]     │
└─────────────────────────────────┘
```

**Features:**
- Number pad with letters
- Auto-format as E.164
- Backspace to delete
- Video call button (left)
- Voice call button (center)
- Shows matching contact names while typing
- Haptic feedback on key press

### 3. Call Screens

#### Outgoing Call (Connecting)
```
┌─────────────────────────────────┐
│                                 │
│                                 │
│         👤                      │
│      John Doe                   │
│                                 │
│    Calling...                   │
│                                 │
│                                 │
│                                 │
│                                 │
│                                 │
│                                 │
│      🔇        📢               │
│     Mute     Speaker            │
│                                 │
│                                 │
│                                 │
│          ⭕                     │
│         End                     │
│                                 │
└─────────────────────────────────┘
```

#### Active Audio Call
```
┌─────────────────────────────────┐
│                                 │
│                                 │
│         👤                      │
│      John Doe                   │
│   +1 555-123-4567               │
│                                 │
│      05:23                      │
│                                 │
│                                 │
│   🔇    🔢    📢                │
│  Mute Keypad Speaker            │
│                                 │
│   ➕    📹    📞                │
│  Add   Video Contacts           │
│                                 │
│          ⭕                     │
│         End                     │
│                                 │
└─────────────────────────────────┘
```

**Features:**
- Large contact photo
- Call duration timer
- 6 action buttons in grid
- Mute (toggle)
- Keypad (for DTMF tones)
- Speaker (toggle)
- Add call (future feature)
- Video (upgrade to video)
- Contacts (browse while on call)
- Red end button

#### Active Video Call
```
┌─────────────────────────────────┐
│  ╔═══════════════════════════╗ │
│  ║                           ║ │
│  ║   Remote Video            ║ │
│  ║   (Full Screen)           ║ │
│  ║                           ║ │
│  ║                           ║ │
│  ║                           ║ │
│  ║  ┌─────────┐              ║ │
│  ║  │ Local   │   05:23      ║ │
│  ║  │ Video   │              ║ │
│  ║  └─────────┘              ║ │
│  ╚═══════════════════════════╝ │
│                                 │
│  🔇  📹  🔄  📢  ⭕             │
│ Mute Off Flip Spkr End          │
└─────────────────────────────────┘
```

**Features:**
- Full screen remote video
- Picture-in-picture local video (draggable)
- Tap to show/hide controls
- Auto-hide controls after 3s
- Mute button
- Video off button (pause camera)
- Flip camera (front/back)
- Speaker button
- End call button
- Double tap to switch PiP position
- Pinch to zoom (optional)

#### Incoming Call (CallKit)
```
┌─────────────────────────────────┐
│                                 │
│                                 │
│         👤                      │
│                                 │
│      John Doe                   │
│   +1 555-123-4567               │
│                                 │
│    📱 iPhone Call               │
│                                 │
│                                 │
│                                 │
│                                 │
│  🔕                    ⏰       │
│ Remind Me            Message    │
│                                 │
│                                 │
│   ⭕              ✅            │
│ Decline          Accept         │
│                                 │
└─────────────────────────────────┘
```

This is the native iOS CallKit UI (system-provided).

### 4. Settings

```
┌─────────────────────────────────┐
│  ← Settings                     │
│                                 │
│  ┌───────────────────────────┐ │
│  │  👤 +1 555-123-4567       │ │
│  │  Tap to edit profile      │ │
│  └───────────────────────────┘ │
│                                 │
│  PREFERENCES                    │
│  ────────────────────────────  │
│  Notifications              >  │
│  ────────────────────────────  │
│  Call Settings              >  │
│  ────────────────────────────  │
│  Privacy                    >  │
│  ────────────────────────────  │
│                                 │
│  ABOUT                          │
│  ────────────────────────────  │
│  Help & Support             >  │
│  ────────────────────────────  │
│  Terms of Service           >  │
│  ────────────────────────────  │
│  Version 1.0.0                  │
│                                 │
│  ────────────────────────────  │
│  Sign Out                       │
│  ────────────────────────────  │
└─────────────────────────────────┘
```

## User Flows

### Complete Call Flow (Outgoing)

```
1. User Opens Keypad
   ↓
2. User Enters Phone Number
   OR
   User Selects Contact
   ↓
3. User Taps Voice/Video Call Button
   ↓
4. App Shows "Connecting..." Screen
   CallKit Shows Native Outgoing UI
   ↓
5. Signaling: Send Call Invitation
   ↓
6. Remote User Receives Push/Notification
   ↓
7. Remote User Accepts Call
   ↓
8. App Shows "Connecting..." → "Connected"
   WebRTC Connection Established
   ↓
9. Active Call Screen
   ↓
10. User Taps End Call
    ↓
11. Call Ended
    Return to Previous Screen
    Call Added to Recents
```

### Complete Call Flow (Incoming)

```
1. App Running (Foreground/Background/Terminated)
   ↓
2. VoIP Push Notification Received
   ↓
3. App Wakes Up (if needed)
   Reports to CallKit
   ↓
4. Native iOS Incoming Call Screen
   (Lock Screen or Full Screen)
   ↓
5. User Accepts Call
   ↓
6. App Receives Accept Callback
   ↓
7. App Sends Acceptance Signal
   WebRTC Setup Begins
   ↓
8. Connection Established
   ↓
9. Active Call Screen
   ↓
10. User Ends Call
    ↓
11. Call Added to Recents
```

## Design System

### Colors

```swift
struct AppColors {
    static let primary = Color.blue
    static let success = Color.green
    static let danger = Color.red
    static let warning = Color.orange

    static let textPrimary = Color.primary
    static let textSecondary = Color.secondary
    static let background = Color(.systemBackground)
    static let secondaryBackground = Color(.secondarySystemBackground)
}
```

### Typography

```swift
struct AppFonts {
    // Headers
    static let largeTitle = Font.largeTitle.weight(.bold)
    static let title = Font.title.weight(.semibold)
    static let title2 = Font.title2.weight(.semibold)

    // Body
    static let body = Font.body
    static let callout = Font.callout
    static let caption = Font.caption

    // Call Screens
    static let contactName = Font.system(size: 28, weight: .semibold)
    static let callStatus = Font.system(size: 18, weight: .regular)
    static let callDuration = Font.system(size: 20, weight: .light)
}
```

### Spacing

```swift
struct AppSpacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 16
    static let lg: CGFloat = 24
    static let xl: CGFloat = 32
}
```

### Components

#### Contact Avatar

```swift
struct ContactAvatar: View {
    let contact: Contact
    let size: CGFloat

    var body: some View {
        if let image = contact.image {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(Circle())
        } else {
            Circle()
                .fill(Color.blue)
                .frame(width: size, height: size)
                .overlay {
                    Text(contact.initials)
                        .foregroundColor(.white)
                        .font(.system(size: size * 0.4, weight: .medium))
                }
        }
    }
}
```

#### Call Button

```swift
struct CallButton: View {
    let icon: String
    let title: String
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 28))
                    .frame(width: 60, height: 60)
                    .background(isActive ? Color.white.opacity(0.3) : Color.clear)
                    .clipShape(Circle())

                Text(title)
                    .font(.caption)
            }
            .foregroundColor(.white)
        }
    }
}
```

## Accessibility

### VoiceOver Support

```swift
// Contact Row
.accessibilityLabel("\(contact.displayName), \(contact.phoneNumber)")
.accessibilityHint("Double tap to call")

// Call Button
.accessibilityLabel("Call")
.accessibilityHint("Double tap to start voice call")

// Mute Button
.accessibilityLabel(isMuted ? "Unmute" : "Mute")
.accessibilityHint("Double tap to \(isMuted ? "unmute" : "mute") microphone")
```

### Dynamic Type

Support all text size settings:

```swift
Text(contact.displayName)
    .font(.body)
    .lineLimit(2)
    .minimumScaleFactor(0.8)
```

### Color Contrast

Ensure WCAG AA compliance:
- Text contrast ratio ≥ 4.5:1
- UI elements contrast ratio ≥ 3:1
- Test with Accessibility Inspector

## Animations

### Smooth Transitions

```swift
// Screen transitions
.transition(.move(edge: .trailing))

// State changes
.animation(.easeInOut(duration: 0.3), value: isConnected)

// Button press
.scaleEffect(isPressed ? 0.95 : 1.0)
```

### Call Connection

```swift
// Pulsing animation while connecting
Circle()
    .stroke(Color.blue, lineWidth: 2)
    .scaleEffect(animationScale)
    .opacity(2 - animationScale)
    .animation(
        Animation.easeInOut(duration: 1.5)
            .repeatForever(autoreverses: false),
        value: animationScale
    )
```

## Loading States

```swift
// Shimmer effect for loading contacts
struct ShimmerView: View {
    @State private var isAnimating = false

    var body: some View {
        LinearGradient(...)
            .offset(x: isAnimating ? 400 : -400)
            .onAppear {
                withAnimation(Animation.linear(duration: 1.5).repeatForever()) {
                    isAnimating = true
                }
            }
    }
}
```

## Error States

### Network Error

```
┌─────────────────────────────────┐
│                                 │
│                                 │
│         ⚠️                      │
│                                 │
│    Connection Failed            │
│                                 │
│  Unable to reach the server.    │
│  Please check your internet     │
│  connection and try again.      │
│                                 │
│  ┌───────────────────────────┐ │
│  │      Try Again            │ │
│  └───────────────────────────┘ │
│                                 │
└─────────────────────────────────┘
```

### Call Failed

```
┌─────────────────────────────────┐
│                                 │
│         👤                      │
│      John Doe                   │
│                                 │
│    ❌ Call Failed               │
│                                 │
│  Unable to connect. Please      │
│  try again later.               │
│                                 │
│  ┌───────────────────────────┐ │
│  │      Call Again           │ │
│  └───────────────────────────┘ │
│                                 │
│  ┌───────────────────────────┐ │
│  │      Cancel               │ │
│  └───────────────────────────┘ │
│                                 │
└─────────────────────────────────┘
```

## Empty States

### No Recent Calls

```
┌─────────────────────────────────┐
│  Recents                        │
│                                 │
│                                 │
│         📞                      │
│                                 │
│    No Recent Calls              │
│                                 │
│  Your call history will appear  │
│  here once you make or receive  │
│  your first call.               │
│                                 │
│                                 │
└─────────────────────────────────┘
```

### No Contacts

```
┌─────────────────────────────────┐
│  Contacts                       │
│                                 │
│                                 │
│         👥                      │
│                                 │
│    No Contacts                  │
│                                 │
│  Grant access to your contacts  │
│  to see who you can call.       │
│                                 │
│  ┌───────────────────────────┐ │
│  │   Allow Access            │ │
│  └───────────────────────────┘ │
│                                 │
└─────────────────────────────────┘
```

## Platform Integration

### Siri Shortcuts

Allow users to create Siri shortcuts for frequent contacts:

```swift
import Intents

func donateCallIntent(contact: Contact) {
    let intent = INStartCallIntent(...)
    intent.suggestedInvocationPhrase = "Call \(contact.displayName)"

    let interaction = INInteraction(intent: intent, response: nil)
    interaction.donate { error in
        // Handle donation
    }
}
```

### Widgets (Optional Future Feature)

Favorites widget showing quick dial buttons.

### Handoff (Optional Future Feature)

Continue calls on other devices.

## Performance Considerations

### Lazy Loading

```swift
LazyVStack {
    ForEach(contacts) { contact in
        ContactRow(contact: contact)
    }
}
```

### Image Caching

Cache contact photos to prevent repeated loading.

### Pagination

Load contacts in batches if list is very large.

## Testing Checklist

- [ ] All screens accessible via VoiceOver
- [ ] Dynamic Type support working
- [ ] Dark mode looks correct
- [ ] Animations smooth (60 fps)
- [ ] No layout issues on different screen sizes
- [ ] Landscape orientation handled
- [ ] iPad layout optimized
- [ ] Loading states show appropriately
- [ ] Error states display correctly
- [ ] Empty states are helpful
- [ ] Haptic feedback feels natural
- [ ] All interactive elements have minimum 44x44 tap target

## Design Files

For high-fidelity mockups, consider using:
- Figma
- Sketch
- Adobe XD

Include iOS UI kit for native components.

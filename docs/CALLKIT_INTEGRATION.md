# CallKit Integration Guide

## Overview

CallKit provides a native iOS calling experience that integrates seamlessly with the system UI. It displays incoming calls on the lock screen, integrates with the Phone app's recent calls list, and provides system-level call controls.

## Why CallKit?

### Benefits

1. **Native UI**: Lock screen incoming call interface
2. **System Integration**: Shows in Phone app's Recents
3. **Bluetooth/CarPlay**: Automatic integration with car systems
4. **Do Not Disturb**: Respects system settings
5. **Professional Experience**: Users expect this for "real" calls
6. **Accessibility**: VoiceOver and other iOS accessibility features

### Requirements

- iOS 10.0+
- Real VoIP service (not for testing only)
- VoIP push notifications (PushKit)
- App Store submission requires working implementation

## Core CallKit Classes

### 1. CXProvider

Manages the lifecycle of calls and communicates with the system.

```swift
import CallKit

class CallManager: NSObject {
    let callController = CXCallController()
    let provider: CXProvider

    override init() {
        // Configure provider
        let configuration = CXProviderConfiguration(localizedName: "MyDialer")
        configuration.supportsVideo = true
        configuration.maximumCallsPerCallGroup = 1
        configuration.supportedHandleTypes = [.phoneNumber]

        // Icons
        if let iconImage = UIImage(named: "CallKitIcon") {
            configuration.iconTemplateImageData = iconImage.pngData()
        }

        // Ringtone
        configuration.ringtoneSound = "ringtone.caf"

        self.provider = CXProvider(configuration: configuration)

        super.init()

        provider.setDelegate(self, queue: nil)
    }
}
```

### 2. CXProviderDelegate

Handles system call actions.

```swift
extension CallManager: CXProviderDelegate {
    func providerDidReset(_ provider: CXProvider) {
        // End all calls
        // Clean up connections
        print("Provider reset")
    }

    func provider(_ provider: CXProvider, perform action: CXStartCallAction) {
        // Called when user initiates outgoing call
        configureAudioSession()

        // Start connecting via WebRTC
        connectCall(action.callUUID)

        // Report call started
        action.fulfill()
    }

    func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
        // Called when user answers incoming call
        configureAudioSession()

        // Accept call via signaling
        answerCall(action.callUUID)

        action.fulfill()
    }

    func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
        // Called when user ends call
        endCall(action.callUUID)

        action.fulfill()
    }

    func provider(_ provider: CXProvider, perform action: CXSetHeldCallAction) {
        // Handle call hold
        action.fulfill()
    }

    func provider(_ provider: CXProvider, perform action: CXSetMutedCallAction) {
        // Handle mute
        muteCall(action.callUUID, isMuted: action.isMuted)
        action.fulfill()
    }

    func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {
        // Start audio
        startAudio()
    }

    func provider(_ provider: CXProvider, didDeactivate audioSession: AVAudioSession) {
        // Stop audio
        stopAudio()
    }
}
```

### 3. CXCallController

Requests call actions to the system.

```swift
// Report outgoing call
func startCall(to phoneNumber: String, isVideo: Bool) {
    let uuid = UUID()
    let handle = CXHandle(type: .phoneNumber, value: phoneNumber)

    let startCallAction = CXStartCallAction(call: uuid, handle: handle)
    startCallAction.isVideo = isVideo

    let transaction = CXTransaction(action: startCallAction)

    callController.request(transaction) { error in
        if let error = error {
            print("Error requesting start call: \(error)")
            return
        }

        // Create call record
        let call = Call(uuid: uuid, phoneNumber: phoneNumber, isVideo: isVideo)
        self.addCall(call)
    }
}

// Report incoming call
func reportIncomingCall(from phoneNumber: String, uuid: UUID, hasVideo: Bool, completion: @escaping (Error?) -> Void) {
    let update = CXCallUpdate()
    update.remoteHandle = CXHandle(type: .phoneNumber, value: phoneNumber)
    update.hasVideo = hasVideo
    update.localizedCallerName = lookupContactName(for: phoneNumber) // Optional

    provider.reportNewIncomingCall(with: uuid, update: update) { error in
        if let error = error {
            print("Failed to report incoming call: \(error)")
            completion(error)
            return
        }

        // Create call record
        let call = Call(uuid: uuid, phoneNumber: phoneNumber, isVideo: hasVideo)
        self.addCall(call)

        completion(nil)
    }
}

// End call
func endCall(uuid: UUID) {
    let endCallAction = CXEndCallAction(call: uuid)
    let transaction = CXTransaction(action: endCallAction)

    callController.request(transaction) { error in
        if let error = error {
            print("Error ending call: \(error)")
        }
    }
}

// Update call with connected state
func callConnected(uuid: UUID) {
    provider.reportOutgoingCall(with: uuid, connectedAt: Date())
}

// Update call failed
func callFailed(uuid: UUID) {
    provider.reportCall(with: uuid, endedAt: Date(), reason: .failed)
}
```

## Complete Call Flow Implementation

### Outgoing Call Flow

```swift
// 1. User taps call button in your app
func initiateCall(to phoneNumber: String, isVideo: Bool) {
    // Start call via CallKit
    callManager.startCall(to: phoneNumber, isVideo: isVideo)
}

// 2. CallKit calls CXStartCallAction
func provider(_ provider: CXProvider, perform action: CXStartCallAction) {
    // Configure audio
    configureAudioSession()

    // Start WebRTC connection
    let call = findCall(uuid: action.callUUID)
    webRTCClient.setupPeerConnection()
    webRTCClient.startLocalMedia(isVideoCall: call.isVideo)

    // Send call invitation via signaling
    signalingClient.initiateCall(to: call.phoneNumber, callId: call.uuid.uuidString) { [weak self] success in
        if success {
            // Report call started
            action.fulfill()
        } else {
            // Report failure
            action.fail()
            self?.provider.reportCall(with: action.callUUID, endedAt: Date(), reason: .failed)
        }
    }
}

// 3. When remote peer answers, signaling server notifies us
func handleCallAccepted(callId: String) {
    guard let uuid = UUID(uuidString: callId) else { return }

    // Start WebRTC offer/answer exchange
    webRTCClient.makeOffer { [weak self] sdp in
        self?.signalingClient.sendOffer(sdp)
    }

    // Report to CallKit that call connected
    provider.reportOutgoingCall(with: uuid, startedConnectingAt: Date())
}

// 4. When media connection establishes
func webRTCClient(_ client: WebRTCClient, didChangeConnectionState state: RTCIceConnectionState) {
    if state == .connected {
        guard let currentCall = currentCall else { return }
        provider.reportOutgoingCall(with: currentCall.uuid, connectedAt: Date())
    }
}
```

### Incoming Call Flow

```swift
// 1. Receive VoIP push notification
func pushRegistry(_ registry: PKPushRegistry,
                 didReceiveIncomingPushWith payload: PKPushPayload,
                 for type: PKPushType,
                 completion: @escaping () -> Void) {

    guard type == .voIP else { return }

    // Extract call info from payload
    guard let callerNumber = payload.dictionaryPayload["caller"] as? String,
          let callIdString = payload.dictionaryPayload["callId"] as? String,
          let uuid = UUID(uuidString: callIdString),
          let hasVideo = payload.dictionaryPayload["hasVideo"] as? Bool else {
        completion()
        return
    }

    // Report incoming call to CallKit
    callManager.reportIncomingCall(
        from: callerNumber,
        uuid: uuid,
        hasVideo: hasVideo
    ) { error in
        completion()
    }
}

// 2. User answers call
func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
    configureAudioSession()

    guard let call = findCall(uuid: action.callUUID) else {
        action.fail()
        return
    }

    // Setup WebRTC
    webRTCClient.setupPeerConnection()
    webRTCClient.startLocalMedia(isVideoCall: call.isVideo)

    // Send acceptance via signaling
    signalingClient.acceptCall(callId: call.uuid.uuidString)

    action.fulfill()
}

// 3. Receive SDP offer from caller
func handleReceivedOffer(_ sdp: RTCSessionDescription, callId: String) {
    webRTCClient.handleRemoteDescription(sdp)

    // Create and send answer
    webRTCClient.makeAnswer { [weak self] answer in
        self?.signalingClient.sendAnswer(answer)
    }
}

// 4. Connection establishes
// Same as outgoing call - WebRTC delegate notifies
```

### Call Ended Flow

```swift
// User ends call
func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
    guard let call = findCall(uuid: action.callUUID) else {
        action.fail()
        return
    }

    // End WebRTC connection
    webRTCClient.close()

    // Notify remote peer
    signalingClient.endCall(callId: call.uuid.uuidString)

    // Remove call from records
    removeCall(call)

    action.fulfill()
}

// Remote peer ends call (via signaling)
func handleCallEnded(callId: String) {
    guard let uuid = UUID(uuidString: callId),
          let call = findCall(uuid: uuid) else { return }

    // End WebRTC
    webRTCClient.close()

    // Report to CallKit
    provider.reportCall(with: uuid, endedAt: Date(), reason: .remoteEnded)

    // Remove from records
    removeCall(call)
}
```

## Call State Management

### Call Model

```swift
class Call {
    let uuid: UUID
    let phoneNumber: String
    let isVideo: Bool
    let isOutgoing: Bool
    var connectedAt: Date?
    var endedAt: Date?

    init(uuid: UUID, phoneNumber: String, isVideo: Bool, isOutgoing: Bool = true) {
        self.uuid = uuid
        self.phoneNumber = phoneNumber
        self.isVideo = isVideo
        self.isOutgoing = isOutgoing
    }
}

class CallManager {
    private var calls: [UUID: Call] = [:]
    private let callsQueue = DispatchQueue(label: "com.app.calls")

    func addCall(_ call: Call) {
        callsQueue.sync {
            calls[call.uuid] = call
        }
    }

    func removeCall(_ call: Call) {
        callsQueue.sync {
            calls.removeValue(forKey: call.uuid)
        }
    }

    func findCall(uuid: UUID) -> Call? {
        callsQueue.sync {
            return calls[uuid]
        }
    }

    var currentCall: Call? {
        callsQueue.sync {
            return calls.values.first(where: { $0.endedAt == nil })
        }
    }
}
```

## Audio Session Configuration

```swift
import AVFoundation

func configureAudioSession() {
    let audioSession = AVAudioSession.sharedInstance()

    do {
        try audioSession.setCategory(.playAndRecord, mode: .voiceChat, options: [])
        try audioSession.setActive(true)
    } catch {
        print("Failed to configure audio session: \(error)")
    }
}

func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {
    // CallKit has activated audio session
    // Start WebRTC audio
    RTCAudioSession.sharedInstance().isAudioEnabled = true
}

func provider(_ provider: CXProvider, didDeactivate audioSession: AVAudioSession) {
    // CallKit has deactivated audio session
    // Stop WebRTC audio
    RTCAudioSession.sharedInstance().isAudioEnabled = false
}
```

## Call Actions

### Mute/Unmute

```swift
func provider(_ provider: CXProvider, perform action: CXSetMutedCallAction) {
    guard let call = findCall(uuid: action.callUUID) else {
        action.fail()
        return
    }

    // Mute local audio
    webRTCClient.muteAudio(action.isMuted)

    action.fulfill()
}

// User taps mute button in app
func toggleMute() {
    guard let call = callManager.currentCall else { return }

    let muteAction = CXSetMutedCallAction(call: call.uuid, muted: !isMuted)
    let transaction = CXTransaction(action: muteAction)

    callController.request(transaction) { error in
        if let error = error {
            print("Error toggling mute: \(error)")
        } else {
            self.isMuted.toggle()
        }
    }
}
```

### Speaker Phone

```swift
// Speaker is managed by iOS automatically for CallKit
// But you can detect route changes

func setupAudioRouteObserver() {
    NotificationCenter.default.addObserver(
        self,
        selector: #selector(audioRouteChanged),
        name: AVAudioSession.routeChangeNotification,
        object: nil
    )
}

@objc func audioRouteChanged(notification: Notification) {
    guard let userInfo = notification.userInfo,
          let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
          let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else {
        return
    }

    switch reason {
    case .newDeviceAvailable:
        // New audio device connected (headphones, bluetooth)
        break
    case .oldDeviceUnavailable:
        // Audio device disconnected
        break
    default:
        break
    }
}
```

### Hold (Optional)

```swift
func provider(_ provider: CXProvider, perform action: CXSetHeldCallAction) {
    guard findCall(uuid: action.callUUID) != nil else {
        action.fail()
        return
    }

    if action.isOnHold {
        // Pause media
        webRTCClient.muteAudio(true)
        webRTCClient.muteVideo(true)
    } else {
        // Resume media
        webRTCClient.muteAudio(false)
        webRTCClient.muteVideo(false)
    }

    action.fulfill()
}
```

## Caller ID & Contact Integration

```swift
import Contacts

func lookupContactName(for phoneNumber: String) -> String? {
    let store = CNContactStore()

    // Normalize phone number
    let normalizedNumber = normalizePhoneNumber(phoneNumber)

    let predicate = CNContact.predicateForContacts(matching: CNPhoneNumber(stringValue: normalizedNumber))
    let keys = [CNContactGivenNameKey, CNContactFamilyNameKey] as [CNKeyDescriptor]

    do {
        let contacts = try store.unifiedContacts(matching: predicate, keysToFetch: keys)
        if let contact = contacts.first {
            return "\(contact.givenName) \(contact.familyName)".trimmingCharacters(in: .whitespaces)
        }
    } catch {
        print("Error fetching contact: \(error)")
    }

    return nil
}

func reportIncomingCall(from phoneNumber: String, uuid: UUID, hasVideo: Bool) {
    let update = CXCallUpdate()
    update.remoteHandle = CXHandle(type: .phoneNumber, value: phoneNumber)
    update.hasVideo = hasVideo

    // Try to get contact name
    if let contactName = lookupContactName(for: phoneNumber) {
        update.localizedCallerName = contactName
    }

    provider.reportNewIncomingCall(with: uuid, update: update) { error in
        // Handle error
    }
}
```

## Call Updates

```swift
// Update call as video
func updateCallToVideo(uuid: UUID) {
    let update = CXCallUpdate()
    update.hasVideo = true

    provider.reportCall(with: uuid, updated: update)
}

// Update caller name (if determined later)
func updateCallerName(uuid: UUID, name: String) {
    let update = CXCallUpdate()
    update.localizedCallerName = name

    provider.reportCall(with: uuid, updated: update)
}
```

## Testing CallKit

### Testing on Simulator

CallKit doesn't fully work on simulator. You'll see console logs but not the UI.

### Testing on Device

1. Run app on physical device
2. Lock device
3. Trigger incoming call via push notification
4. Verify incoming call UI appears on lock screen

### Common Issues

**Issue**: CallKit UI doesn't appear
- **Fix**: Ensure VoIP push capability is enabled
- **Fix**: Report incoming call BEFORE VoIP push completion handler returns

**Issue**: Audio doesn't work
- **Fix**: Properly handle `didActivate`/`didDeactivate` audio session
- **Fix**: Configure RTCAudioSession correctly

**Issue**: App crashes on call end
- **Fix**: Ensure all actions are fulfilled or failed
- **Fix**: Don't access released WebRTC objects

## Best Practices

### 1. Always Fulfill Actions

```swift
func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
    // Even if something goes wrong, fulfill or fail the action
    defer {
        if !actionCompleted {
            action.fail()
        }
    }

    // Your logic here
    // ...

    action.fulfill()
    actionCompleted = true
}
```

### 2. UUID Management

- Generate UUID when creating outgoing call
- Receive UUID in push notification for incoming call
- Use same UUID throughout call lifecycle
- Never reuse UUIDs

### 3. Audio Session

- Let CallKit manage audio session
- Use `didActivate`/`didDeactivate` callbacks
- Don't manually activate/deactivate during call

### 4. Background Mode

Enable required capabilities in Xcode:
- Voice over IP
- Audio, AirPlay, and Picture in Picture
- Background modes → Voice over IP

### 5. Error Handling

Always handle errors gracefully:

```swift
callController.request(transaction) { error in
    if let error = error {
        // Log error
        print("CallKit error: \(error)")

        // Show user-friendly message
        self.showAlert("Call Failed", "Unable to place call. Please try again.")

        // Clean up
        self.cleanup()
    }
}
```

## App Store Requirements

To pass App Store review with CallKit:

1. **Working VoIP service**: Must actually place calls
2. **Push notifications**: Must use VoIP push
3. **Privacy**: Explain why you need CallKit in App Store description
4. **No abuse**: Don't use CallKit for non-VoIP purposes

## Complete CallKit Manager Example

```swift
import CallKit
import AVFoundation

class CallKitManager: NSObject {

    static let shared = CallKitManager()

    private let provider: CXProvider
    private let callController = CXCallController()
    private var calls: [UUID: Call] = [:]

    private override init() {
        let config = CXProviderConfiguration(localizedName: "WebRTC Dialer")
        config.supportsVideo = true
        config.maximumCallsPerCallGroup = 1
        config.supportedHandleTypes = [.phoneNumber]

        self.provider = CXProvider(configuration: config)
        super.init()

        provider.setDelegate(self, queue: nil)
    }

    // MARK: - Outgoing Calls

    func startCall(phoneNumber: String, isVideo: Bool, completion: @escaping (UUID?) -> Void) {
        let uuid = UUID()
        let handle = CXHandle(type: .phoneNumber, value: phoneNumber)
        let startAction = CXStartCallAction(call: uuid, handle: handle)
        startAction.isVideo = isVideo

        let transaction = CXTransaction(action: startAction)

        callController.request(transaction) { [weak self] error in
            if let error = error {
                print("Start call error: \(error)")
                completion(nil)
                return
            }

            let call = Call(uuid: uuid, phoneNumber: phoneNumber, isVideo: isVideo)
            self?.calls[uuid] = call
            completion(uuid)
        }
    }

    // MARK: - Incoming Calls

    func reportIncomingCall(uuid: UUID, phoneNumber: String, hasVideo: Bool, completion: @escaping (Error?) -> Void) {
        let update = CXCallUpdate()
        update.remoteHandle = CXHandle(type: .phoneNumber, value: phoneNumber)
        update.hasVideo = hasVideo

        provider.reportNewIncomingCall(with: uuid, update: update) { [weak self] error in
            if error == nil {
                let call = Call(uuid: uuid, phoneNumber: phoneNumber, isVideo: hasVideo, isOutgoing: false)
                self?.calls[uuid] = call
            }
            completion(error)
        }
    }

    // MARK: - End Calls

    func endCall(uuid: UUID) {
        let endAction = CXEndCallAction(call: uuid)
        let transaction = CXTransaction(action: endAction)

        callController.request(transaction) { error in
            if let error = error {
                print("End call error: \(error)")
            }
        }
    }

    // MARK: - Call Updates

    func callConnected(uuid: UUID) {
        provider.reportOutgoingCall(with: uuid, connectedAt: Date())
        calls[uuid]?.connectedAt = Date()
    }

    func callFailed(uuid: UUID) {
        provider.reportCall(with: uuid, endedAt: Date(), reason: .failed)
        calls.removeValue(forKey: uuid)
    }
}

// MARK: - CXProviderDelegate

extension CallKitManager: CXProviderDelegate {

    func providerDidReset(_ provider: CXProvider) {
        calls.removeAll()
    }

    func provider(_ provider: CXProvider, perform action: CXStartCallAction) {
        configureAudioSession()
        // Notify app to start call
        NotificationCenter.default.post(name: .startCallAction, object: action.callUUID)
        action.fulfill()
    }

    func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
        configureAudioSession()
        // Notify app to answer call
        NotificationCenter.default.post(name: .answerCallAction, object: action.callUUID)
        action.fulfill()
    }

    func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
        // Notify app to end call
        NotificationCenter.default.post(name: .endCallAction, object: action.callUUID)
        calls.removeValue(forKey: action.callUUID)
        action.fulfill()
    }

    func provider(_ provider: CXProvider, perform action: CXSetMutedCallAction) {
        // Notify app to mute/unmute
        NotificationCenter.default.post(
            name: .muteCallAction,
            object: action.callUUID,
            userInfo: ["isMuted": action.isMuted]
        )
        action.fulfill()
    }

    func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {
        // Start audio
        RTCAudioSession.sharedInstance().isAudioEnabled = true
    }

    func provider(_ provider: CXProvider, didDeactivate audioSession: AVAudioSession) {
        // Stop audio
        RTCAudioSession.sharedInstance().isAudioEnabled = false
    }

    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .voiceChat)
            try session.setActive(true)
        } catch {
            print("Audio session error: \(error)")
        }
    }
}

// Notification names
extension Notification.Name {
    static let startCallAction = Notification.Name("startCallAction")
    static let answerCallAction = Notification.Name("answerCallAction")
    static let endCallAction = Notification.Name("endCallAction")
    static let muteCallAction = Notification.Name("muteCallAction")
}
```

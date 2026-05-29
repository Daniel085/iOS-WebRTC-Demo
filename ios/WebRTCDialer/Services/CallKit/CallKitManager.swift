//
//  CallKitManager.swift
//  WebRTCDialer
//
//  CallKit integration for native iOS call experience
//

import Foundation
import CallKit
import AVFoundation

/// Delegate protocol for CallKit events
protocol CallKitManagerDelegate: AnyObject {
    func callKitManager(_ manager: CallKitManager, didStartCall call: Call)
    func callKitManager(_ manager: CallKitManager, didAnswerCall call: Call)
    func callKitManager(_ manager: CallKitManager, didEndCall call: Call)
    func callKitManager(_ manager: CallKitManager, didHoldCall call: Call, onHold: Bool)
    func callKitManager(_ manager: CallKitManager, didMuteCall call: Call, muted: Bool)
}

/// Manages all CallKit interactions for the app
class CallKitManager: NSObject {

    // MARK: - Singleton

    static let shared = CallKitManager()

    // MARK: - Properties

    weak var delegate: CallKitManagerDelegate?

    private let provider: CXProvider
    private let callController = CXCallController()

    /// Active calls tracked by UUID
    private var activeCalls: [UUID: Call] = [:]

    /// Queue for CallKit operations
    private let callQueue = DispatchQueue(label: "com.webrtcdialer.callkit", qos: .userInitiated)

    // MARK: - Initialization

    private override init() {
        // Configure provider
        let configuration = CXProviderConfiguration()
        configuration.supportsVideo = true
        configuration.maximumCallsPerCallGroup = 1
        configuration.maximumCallGroups = 1
        configuration.supportedHandleTypes = [.phoneNumber]

        // App name shown in call UI
        configuration.localizedName = "WebRTC Dialer"

        // Ringtone (use default system ringtone)
        configuration.ringtoneSound = "Ringtone.caf"

        // Icon template for CallKit UI
        if let iconImage = UIImage(named: "CallKitIcon") {
            configuration.iconTemplateImageData = iconImage.pngData()
        }

        provider = CXProvider(configuration: configuration)

        super.init()

        provider.setDelegate(self, queue: nil)

        print("✅ CallKitManager initialized")
    }

    // MARK: - Public Methods

    /// Start an outgoing call
    /// - Parameters:
    ///   - phoneNumber: The phone number to call
    ///   - hasVideo: Whether this is a video call
    ///   - completion: Completion handler with success/failure
    func startCall(phoneNumber: String, hasVideo: Bool = false, completion: @escaping (Result<Call, Error>) -> Void) {
        let call = Call(
            id: UUID(),
            phoneNumber: phoneNumber,
            isIncoming: false,
            hasVideo: hasVideo,
            state: .connecting
        )

        activeCalls[call.id] = call

        let handle = CXHandle(type: .phoneNumber, value: phoneNumber)
        let startCallAction = CXStartCallAction(call: call.id, handle: handle)
        startCallAction.isVideo = hasVideo

        let transaction = CXTransaction(action: startCallAction)

        callQueue.async { [weak self] in
            self?.callController.request(transaction) { error in
                DispatchQueue.main.async {
                    if let error = error {
                        print("❌ Failed to start call: \(error.localizedDescription)")
                        self?.activeCalls.removeValue(forKey: call.id)
                        completion(.failure(error))
                    } else {
                        print("✅ Call started: \(phoneNumber)")
                        completion(.success(call))
                    }
                }
            }
        }
    }

    /// Report an incoming call to CallKit
    /// - Parameters:
    ///   - phoneNumber: The caller's phone number
    ///   - hasVideo: Whether this is a video call
    ///   - callId: Optional UUID for the call (generates new if not provided)
    ///   - completion: Completion handler
    func reportIncomingCall(
        phoneNumber: String,
        hasVideo: Bool = false,
        callId: UUID = UUID(),
        completion: @escaping (Error?) -> Void
    ) {
        let call = Call(
            id: callId,
            phoneNumber: phoneNumber,
            isIncoming: true,
            hasVideo: hasVideo,
            state: .ringing
        )

        activeCalls[call.id] = call

        let update = CXCallUpdate()
        update.remoteHandle = CXHandle(type: .phoneNumber, value: phoneNumber)
        update.hasVideo = hasVideo
        update.localizedCallerName = phoneNumber // Can be enhanced with contact lookup
        update.supportsHolding = true
        update.supportsGrouping = false
        update.supportsUngrouping = false
        update.supportsDTMF = false

        provider.reportNewIncomingCall(with: call.id, update: update) { error in
            DispatchQueue.main.async {
                if let error = error {
                    print("❌ Failed to report incoming call: \(error.localizedDescription)")
                    self.activeCalls.removeValue(forKey: call.id)
                    completion(error)
                } else {
                    print("✅ Incoming call reported: \(phoneNumber)")
                    completion(nil)
                }
            }
        }
    }

    /// Answer an incoming call
    /// - Parameters:
    ///   - callId: The UUID of the call to answer
    ///   - completion: Completion handler
    func answerCall(_ callId: UUID, completion: @escaping (Error?) -> Void) {
        let answerAction = CXAnswerCallAction(call: callId)
        let transaction = CXTransaction(action: answerAction)

        callQueue.async { [weak self] in
            self?.callController.request(transaction) { error in
                DispatchQueue.main.async {
                    if let error = error {
                        print("❌ Failed to answer call: \(error.localizedDescription)")
                        completion(error)
                    } else {
                        print("✅ Call answered: \(callId)")
                        completion(nil)
                    }
                }
            }
        }
    }

    /// End a call
    /// - Parameters:
    ///   - callId: The UUID of the call to end
    ///   - completion: Completion handler
    func endCall(_ callId: UUID, completion: @escaping (Error?) -> Void) {
        let endAction = CXEndCallAction(call: callId)
        let transaction = CXTransaction(action: endAction)

        callQueue.async { [weak self] in
            self?.callController.request(transaction) { error in
                DispatchQueue.main.async {
                    if let error = error {
                        print("❌ Failed to end call: \(error.localizedDescription)")
                        completion(error)
                    } else {
                        print("✅ Call ended: \(callId)")
                        self?.activeCalls.removeValue(forKey: callId)
                        completion(nil)
                    }
                }
            }
        }
    }

    /// Hold or unhold a call
    /// - Parameters:
    ///   - callId: The UUID of the call
    ///   - onHold: Whether to hold or unhold
    ///   - completion: Completion handler
    func setHold(_ callId: UUID, onHold: Bool, completion: @escaping (Error?) -> Void) {
        let holdAction = CXSetHeldCallAction(call: callId, onHold: onHold)
        let transaction = CXTransaction(action: holdAction)

        callQueue.async { [weak self] in
            self?.callController.request(transaction) { error in
                DispatchQueue.main.async {
                    if let error = error {
                        print("❌ Failed to set hold: \(error.localizedDescription)")
                        completion(error)
                    } else {
                        print("✅ Call hold changed: \(onHold)")
                        completion(nil)
                    }
                }
            }
        }
    }

    /// Mute or unmute a call
    /// - Parameters:
    ///   - callId: The UUID of the call
    ///   - muted: Whether to mute or unmute
    ///   - completion: Completion handler
    func setMuted(_ callId: UUID, muted: Bool, completion: @escaping (Error?) -> Void) {
        let muteAction = CXSetMutedCallAction(call: callId, muted: muted)
        let transaction = CXTransaction(action: muteAction)

        callQueue.async { [weak self] in
            self?.callController.request(transaction) { error in
                DispatchQueue.main.async {
                    if let error = error {
                        print("❌ Failed to set mute: \(error.localizedDescription)")
                        completion(error)
                    } else {
                        print("✅ Call mute changed: \(muted)")
                        completion(nil)
                    }
                }
            }
        }
    }

    /// Update call state (for display purposes)
    /// - Parameters:
    ///   - callId: The UUID of the call
    ///   - hasVideo: Whether call has video
    ///   - completion: Completion handler
    func updateCall(_ callId: UUID, hasVideo: Bool? = nil, completion: ((Error?) -> Void)? = nil) {
        let update = CXCallUpdate()

        if let call = activeCalls[callId] {
            update.remoteHandle = CXHandle(type: .phoneNumber, value: call.phoneNumber)
            update.localizedCallerName = call.phoneNumber
        }

        if let hasVideo = hasVideo {
            update.hasVideo = hasVideo
        }

        provider.reportCall(with: callId, updated: update)
        completion?(nil)
    }

    /// Report that a call has connected
    /// - Parameter callId: The UUID of the call
    func reportOutgoingCallConnected(_ callId: UUID) {
        guard activeCalls[callId] != nil else { return }

        provider.reportOutgoingCall(with: callId, connectedAt: Date())
        activeCalls[callId]?.state = .connected

        print("✅ Outgoing call connected: \(callId)")
    }

    /// Report that an outgoing call has started connecting
    /// - Parameter callId: The UUID of the call
    func reportOutgoingCallStartedConnecting(_ callId: UUID) {
        guard activeCalls[callId] != nil else { return }

        provider.reportOutgoingCall(with: callId, startedConnectingAt: Date())
        activeCalls[callId]?.state = .connecting

        print("✅ Outgoing call started connecting: \(callId)")
    }

    /// Get active call by UUID
    /// - Parameter callId: The UUID of the call
    /// - Returns: The Call object if found
    func getCall(_ callId: UUID) -> Call? {
        return activeCalls[callId]
    }

    /// Get all active calls
    /// - Returns: Array of active calls
    func getActiveCalls() -> [Call] {
        return Array(activeCalls.values)
    }

    /// Check if there are any active calls
    var hasActiveCalls: Bool {
        return !activeCalls.isEmpty
    }
}

// MARK: - CXProviderDelegate

extension CallKitManager: CXProviderDelegate {

    func providerDidReset(_ provider: CXProvider) {
        print("⚠️ CallKit provider did reset")

        // End all active calls
        activeCalls.removeAll()
    }

    func provider(_ provider: CXProvider, perform action: CXStartCallAction) {
        guard let call = activeCalls[action.callUUID] else {
            action.fail()
            return
        }

        // Configure audio session
        configureAudioSession()

        // Update call state
        call.state = .connecting

        // Notify that call is starting
        provider.reportOutgoingCall(with: action.callUUID, startedConnectingAt: Date())

        // Notify delegate
        delegate?.callKitManager(self, didStartCall: call)

        // Fulfill the action
        action.fulfill()
    }

    func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
        guard let call = activeCalls[action.callUUID] else {
            action.fail()
            return
        }

        // Configure audio session
        configureAudioSession()

        // Update call state
        call.state = .connected

        // Notify delegate
        delegate?.callKitManager(self, didAnswerCall: call)

        // Fulfill the action
        action.fulfill()
    }

    func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
        guard let call = activeCalls[action.callUUID] else {
            action.fail()
            return
        }

        // Update call state
        call.state = .ended

        // Notify delegate
        delegate?.callKitManager(self, didEndCall: call)

        // Remove from active calls
        activeCalls.removeValue(forKey: action.callUUID)

        // Fulfill the action
        action.fulfill()
    }

    func provider(_ provider: CXProvider, perform action: CXSetHeldCallAction) {
        guard let call = activeCalls[action.callUUID] else {
            action.fail()
            return
        }

        // Update call state
        call.isOnHold = action.isOnHold

        // Notify delegate
        delegate?.callKitManager(self, didHoldCall: call, onHold: action.isOnHold)

        // Fulfill the action
        action.fulfill()
    }

    func provider(_ provider: CXProvider, perform action: CXSetMutedCallAction) {
        guard let call = activeCalls[action.callUUID] else {
            action.fail()
            return
        }

        // Update call state
        call.isMuted = action.isMuted

        // Notify delegate
        delegate?.callKitManager(self, didMuteCall: call, muted: action.isMuted)

        // Fulfill the action
        action.fulfill()
    }

    func provider(_ provider: CXProvider, timedOutPerforming action: CXAction) {
        print("⚠️ CallKit action timed out: \(action)")
        action.fail()
    }

    func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {
        print("✅ Audio session activated")

        // Audio session is now active
        // WebRTC will use this when we integrate it
    }

    func provider(_ provider: CXProvider, didDeactivate audioSession: AVAudioSession) {
        print("✅ Audio session deactivated")

        // Audio session is now inactive
    }

    // MARK: - Audio Configuration

    private func configureAudioSession() {
        let audioSession = AVAudioSession.sharedInstance()

        do {
            try audioSession.setCategory(.playAndRecord, mode: .voiceChat, options: [.allowBluetooth, .allowBluetoothA2DP])
            try audioSession.setActive(true)
            print("✅ Audio session configured")
        } catch {
            print("❌ Failed to configure audio session: \(error)")
        }
    }
}

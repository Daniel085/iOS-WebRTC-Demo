//
//  CallKitManager.swift
//  WebRTCDialer
//
//  Thin adapter over CXProvider / CXCallController (see docs/CALLKIT_INTEGRATION.md).
//
//  It owns no call state: CallManager keeps the Call objects and performs the
//  actual work (signaling + WebRTC) when CallKit asks for an action. This
//  class only translates between CallKit's transaction model and the delegate.
//

import Foundation
@preconcurrency import CallKit
import AVFoundation

@MainActor
protocol CallKitManagerDelegate: AnyObject {
    /// The system wants the outgoing call to start (user tapped call in-app).
    func callKitManager(_ manager: CallKitManager, performStartCall uuid: UUID) -> Bool
    /// The user answered (in-app or on the native incoming-call screen).
    func callKitManager(_ manager: CallKitManager, performAnswerCall uuid: UUID) -> Bool
    /// The user ended or declined the call.
    func callKitManager(_ manager: CallKitManager, performEndCall uuid: UUID) -> Bool
    func callKitManager(_ manager: CallKitManager, performSetMuted muted: Bool, uuid: UUID) -> Bool
    func callKitManager(_ manager: CallKitManager, performSetHeld onHold: Bool, uuid: UUID) -> Bool
    func callKitManager(_ manager: CallKitManager, performDTMF digits: String, uuid: UUID) -> Bool
    func callKitManagerDidReset(_ manager: CallKitManager)
    func callKitManager(_ manager: CallKitManager, didActivateAudioSession session: AVAudioSession)
    func callKitManager(_ manager: CallKitManager, didDeactivateAudioSession session: AVAudioSession)
}

@MainActor
final class CallKitManager: NSObject {

    static let shared = CallKitManager()

    weak var delegate: CallKitManagerDelegate?

    private let provider: CXProvider
    private let callController = CXCallController()

    private override init() {
        let configuration = CXProviderConfiguration()
        configuration.supportsVideo = true
        configuration.maximumCallGroups = 1
        configuration.maximumCallsPerCallGroup = 1
        configuration.supportedHandleTypes = [.phoneNumber]
        configuration.includesCallsInRecents = true
        provider = CXProvider(configuration: configuration)
        super.init()
        // nil queue = main queue, which is where the delegate expects to run.
        provider.setDelegate(self, queue: nil)
        print("☎️ [CallKit] Provider configured")
    }

    // MARK: Requests (app → system)

    func requestStartCall(uuid: UUID, handle: String, hasVideo: Bool, completion: @escaping @MainActor (Error?) -> Void) {
        let action = CXStartCallAction(call: uuid, handle: CXHandle(type: .phoneNumber, value: handle))
        action.isVideo = hasVideo
        request(action, completion: completion)
    }

    /// Tell the system a call gained or lost video (mid-call toggle).
    func reportCallUpdated(uuid: UUID, hasVideo: Bool) {
        let update = CXCallUpdate()
        update.hasVideo = hasVideo
        provider.reportCall(with: uuid, updated: update)
    }

    func reportIncomingCall(uuid: UUID, handle: String, hasVideo: Bool, completion: @escaping @MainActor (Error?) -> Void) {
        let update = CXCallUpdate()
        update.remoteHandle = CXHandle(type: .phoneNumber, value: handle)
        update.localizedCallerName = handle
        update.hasVideo = hasVideo
        update.supportsHolding = true
        update.supportsGrouping = false
        update.supportsUngrouping = false
        update.supportsDTMF = true
        provider.reportNewIncomingCall(with: uuid, update: update) { error in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    if let error { print("☎️ [CallKit] reportNewIncomingCall failed: \(error.localizedDescription)") }
                    completion(error)
                }
            }
        }
    }

    func requestAnswerCall(uuid: UUID, completion: @escaping @MainActor (Error?) -> Void) {
        request(CXAnswerCallAction(call: uuid), completion: completion)
    }

    func requestEndCall(uuid: UUID, completion: @escaping @MainActor (Error?) -> Void) {
        request(CXEndCallAction(call: uuid), completion: completion)
    }

    func requestSetMuted(uuid: UUID, muted: Bool, completion: @escaping @MainActor (Error?) -> Void) {
        request(CXSetMutedCallAction(call: uuid, muted: muted), completion: completion)
    }

    func requestSetHeld(uuid: UUID, onHold: Bool, completion: @escaping @MainActor (Error?) -> Void) {
        request(CXSetHeldCallAction(call: uuid, onHold: onHold), completion: completion)
    }

    private func request(_ action: CXAction, completion: @escaping @MainActor (Error?) -> Void) {
        callController.request(CXTransaction(action: action)) { error in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    if let error { print("☎️ [CallKit] \(type(of: action)) failed: \(error.localizedDescription)") }
                    completion(error)
                }
            }
        }
    }

    // MARK: Reports (app → system, no user action)

    func reportOutgoingCallStartedConnecting(uuid: UUID) {
        provider.reportOutgoingCall(with: uuid, startedConnectingAt: Date())
    }

    func reportOutgoingCallConnected(uuid: UUID) {
        provider.reportOutgoingCall(with: uuid, connectedAt: Date())
    }

    func reportCallEnded(uuid: UUID, reason: CXCallEndedReason) {
        provider.reportCall(with: uuid, endedAt: Date(), reason: reason)
    }

    /// Whether the system currently tracks this call (used to avoid reporting
    /// an end for a call CallKit never accepted).
    func isTracking(uuid: UUID) -> Bool {
        callController.callObserver.calls.contains { $0.uuid == uuid }
    }
}

// MARK: - CXProviderDelegate

extension CallKitManager: CXProviderDelegate {

    nonisolated func providerDidReset(_ provider: CXProvider) {
        MainActor.assumeIsolated {
            print("☎️ [CallKit] Provider reset")
            delegate?.callKitManagerDidReset(self)
        }
    }

    nonisolated func provider(_ provider: CXProvider, perform action: CXStartCallAction) {
        MainActor.assumeIsolated {
            print("☎️ [CallKit] Perform start \(action.callUUID)")
            if delegate?.callKitManager(self, performStartCall: action.callUUID) == true {
                action.fulfill()
            } else {
                action.fail()
            }
        }
    }

    nonisolated func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
        MainActor.assumeIsolated {
            print("☎️ [CallKit] Perform answer \(action.callUUID)")
            if delegate?.callKitManager(self, performAnswerCall: action.callUUID) == true {
                action.fulfill()
            } else {
                action.fail()
            }
        }
    }

    nonisolated func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
        MainActor.assumeIsolated {
            print("☎️ [CallKit] Perform end \(action.callUUID)")
            if delegate?.callKitManager(self, performEndCall: action.callUUID) == true {
                action.fulfill()
            } else {
                action.fail()
            }
        }
    }

    nonisolated func provider(_ provider: CXProvider, perform action: CXSetMutedCallAction) {
        MainActor.assumeIsolated {
            if delegate?.callKitManager(self, performSetMuted: action.isMuted, uuid: action.callUUID) == true {
                action.fulfill()
            } else {
                action.fail()
            }
        }
    }

    nonisolated func provider(_ provider: CXProvider, perform action: CXSetHeldCallAction) {
        MainActor.assumeIsolated {
            if delegate?.callKitManager(self, performSetHeld: action.isOnHold, uuid: action.callUUID) == true {
                action.fulfill()
            } else {
                action.fail()
            }
        }
    }

    nonisolated func provider(_ provider: CXProvider, perform action: CXPlayDTMFCallAction) {
        MainActor.assumeIsolated {
            if delegate?.callKitManager(self, performDTMF: action.digits, uuid: action.callUUID) == true {
                action.fulfill()
            } else {
                action.fail()
            }
        }
    }

    nonisolated func provider(_ provider: CXProvider, timedOutPerforming action: CXAction) {
        print("☎️ [CallKit] Action timed out: \(action)")
        action.fail()
    }

    nonisolated func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {
        MainActor.assumeIsolated {
            print("☎️ [CallKit] Audio session activated")
            delegate?.callKitManager(self, didActivateAudioSession: audioSession)
        }
    }

    nonisolated func provider(_ provider: CXProvider, didDeactivate audioSession: AVAudioSession) {
        MainActor.assumeIsolated {
            print("☎️ [CallKit] Audio session deactivated")
            delegate?.callKitManager(self, didDeactivateAudioSession: audioSession)
        }
    }
}

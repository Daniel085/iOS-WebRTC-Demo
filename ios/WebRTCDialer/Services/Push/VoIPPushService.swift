//
//  VoIPPushService.swift
//  WebRTCDialer
//
//  PushKit registration. The token is logged and POSTed to /api/user/voip-token
//  so the backend can wake this device for calls when the socket is down.
//
//  Note: the server's APNs key is not configured yet, so pushes are only
//  logged server-side for now. Incoming pushes are still handled correctly
//  (reported to CallKit before the completion handler returns, as iOS requires).
//

import Foundation
import PushKit
import UIKit

@MainActor
final class VoIPPushService: NSObject {

    static let shared = VoIPPushService()

    private var registry: PKPushRegistry?

    /// Hex-encoded VoIP token, if the system has issued one.
    private(set) var deviceToken: String? {
        get { UserDefaults.standard.string(forKey: Constants.UserDefaults.voipDeviceToken) }
        set { UserDefaults.standard.set(newValue, forKey: Constants.UserDefaults.voipDeviceToken) }
    }

    private override init() {
        super.init()
    }

    /// Start PushKit. Idempotent. Call once the app is launched (incoming
    /// pushes can arrive before the user opens the UI).
    func register() {
        guard registry == nil else { return }
        let registry = PKPushRegistry(queue: .main)
        registry.delegate = self
        registry.desiredPushTypes = [.voIP]
        self.registry = registry
        log("PushKit started; waiting for token")
    }

    /// Re-send the stored token after login (the token may have arrived
    /// before the user authenticated).
    func uploadTokenIfNeeded() {
        guard let token = deviceToken else { return }
        Task { await upload(token: token) }
    }

    private func upload(token: String) async {
        guard let jwt = AuthenticationService.shared.authToken else {
            log("Not authenticated; token upload deferred")
            return
        }
        guard let url = URL(string: "\(Constants.API.baseURL)/api/user/voip-token") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(jwt)", forHTTPHeaderField: "Authorization")
        var body: [String: String] = ["token": token]
        if let deviceId = UIDevice.current.identifierForVendor?.uuidString {
            body["deviceId"] = deviceId
        }
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            log(status == 200 ? "Token registered with backend" : "Token upload returned HTTP \(status)")
        } catch {
            log("Token upload failed: \(error.localizedDescription)")
        }
    }

    private func log(_ message: String) {
        print("📲 [VoIP Push] \(message)")
    }
}

// MARK: - PKPushRegistryDelegate (delivered on the main queue)

extension VoIPPushService: PKPushRegistryDelegate {

    nonisolated func pushRegistry(_ registry: PKPushRegistry, didUpdate pushCredentials: PKPushCredentials, for type: PKPushType) {
        guard type == .voIP else { return }
        let token = pushCredentials.token.map { String(format: "%02x", $0) }.joined()
        MainActor.assumeIsolated {
            log("Token: \(token)")
            deviceToken = token
            Task { await upload(token: token) }
        }
    }

    nonisolated func pushRegistry(_ registry: PKPushRegistry, didInvalidatePushTokenFor type: PKPushType) {
        guard type == .voIP else { return }
        MainActor.assumeIsolated {
            log("Token invalidated")
            deviceToken = nil
        }
    }

    nonisolated func pushRegistry(_ registry: PKPushRegistry, didReceiveIncomingPushWith payload: PKPushPayload, for type: PKPushType, completion: @escaping () -> Void) {
        guard type == .voIP else { completion(); return }
        let dict = payload.dictionaryPayload
        // Payload shape from backend/src/services/voip-push.js: {callId, caller, hasVideo}
        let callId = dict["callId"] as? String
        let caller = dict["caller"] as? String
        let hasVideo = dict["hasVideo"] as? Bool ?? false
        MainActor.assumeIsolated {
            log("Incoming push: callId=\(callId ?? "-") caller=\(caller ?? "-")")
            CallManager.shared.handleVoIPPush(callId: callId, caller: caller, hasVideo: hasVideo, completion: completion)
        }
    }
}

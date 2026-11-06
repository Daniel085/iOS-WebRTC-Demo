//
//  SignalingClient.swift
//  WebRTCDialer
//
//  Socket.IO client for the backend signaling protocol (see docs/SIGNALING_SERVER.md).
//
//  The client is deliberately UI-agnostic: it knows nothing about Call objects,
//  CallKit or WebRTC. It turns socket events into typed delegate callbacks and
//  exposes typed emit methods. CallManager sits on top of it. A future SIP
//  gateway can plug into the same CallManager path without touching this file.
//

import Foundation
import Combine
import SocketIO

// MARK: - Wire types

/// `incoming-call` payload.
struct SignalingIncomingCall {
    let callId: String
    let from: String
    let hasVideo: Bool
}

/// ICE candidate as sent over the wire. The JSON shape matches the browser
/// `RTCIceCandidateInit` dictionary so a web client could interoperate.
struct SignalingIceCandidate {
    let sdp: String
    let sdpMid: String?
    let sdpMLineIndex: Int32

    var json: [String: Any] {
        var dict: [String: Any] = [
            "candidate": sdp,
            "sdpMLineIndex": Int(sdpMLineIndex)
        ]
        if let sdpMid { dict["sdpMid"] = sdpMid }
        return dict
    }

    init(sdp: String, sdpMid: String?, sdpMLineIndex: Int32) {
        self.sdp = sdp
        self.sdpMid = sdpMid
        self.sdpMLineIndex = sdpMLineIndex
    }

    init?(json: Any?) {
        guard let dict = json as? [String: Any],
              let sdp = dict["candidate"] as? String ?? dict["sdp"] as? String else {
            return nil
        }
        self.sdp = sdp
        self.sdpMid = dict["sdpMid"] as? String
        if let index = dict["sdpMLineIndex"] as? Int {
            self.sdpMLineIndex = Int32(index)
        } else if let index = dict["sdpMLineIndex"] as? Int32 {
            self.sdpMLineIndex = index
        } else {
            self.sdpMLineIndex = 0
        }
    }
}

// MARK: - Delegate

/// All callbacks are delivered on the main actor, in the order the server sent them.
@MainActor
protocol SignalingClientDelegate: AnyObject {
    func signalingClient(_ client: SignalingClient, didChangeState state: SignalingClient.ConnectionState)
    func signalingClient(_ client: SignalingClient, didReceiveIncomingCall call: SignalingIncomingCall)
    func signalingClient(_ client: SignalingClient, didReceiveOffer sdp: String, callId: String, from: String?)
    func signalingClient(_ client: SignalingClient, didReceiveAnswer sdp: String, callId: String, from: String?)
    func signalingClient(_ client: SignalingClient, didReceiveIceCandidate candidate: SignalingIceCandidate, callId: String)
    func signalingClient(_ client: SignalingClient, callWasAnswered callId: String, by: String?)
    func signalingClient(_ client: SignalingClient, callWasRejected callId: String, reason: String?)
    func signalingClient(_ client: SignalingClient, callDidEnd callId: String, reason: String?)
    func signalingClient(_ client: SignalingClient, didReceiveCallError message: String, callId: String?)
}

// MARK: - Client

@MainActor
final class SignalingClient: ObservableObject {

    enum ConnectionState: Equatable {
        case disconnected
        case connecting
        /// Socket is up but `register` has not been acknowledged yet.
        case connected
        /// `registered` received: the server will route calls to this socket.
        case registered
        case failed(String)

        var isUsable: Bool { self == .registered }
    }

    weak var delegate: SignalingClientDelegate?

    @Published private(set) var state: ConnectionState = .disconnected

    /// Phone number the server registered this socket under.
    @Published private(set) var registeredPhoneNumber: String?

    private var manager: SocketManager?
    private var socket: SocketIOClient?

    /// Token provider, injected so tests or a SIP gateway can supply their own.
    private let tokenProvider: @MainActor () -> String?

    init(tokenProvider: @escaping @MainActor () -> String? = { AuthenticationService.shared.authToken }) {
        self.tokenProvider = tokenProvider
    }

    var isConnected: Bool { state.isUsable }

    // MARK: Connection lifecycle

    /// Connect (or reconnect) to `Constants.API.signalingURL` using the current JWT.
    /// Safe to call repeatedly: an existing connection to the same URL is kept.
    func connect() {
        guard let token = tokenProvider() else {
            log("No auth token; not connecting")
            setState(.failed("Not authenticated"))
            return
        }

        let urlString = Constants.API.signalingURL
        guard let url = URL(string: urlString) else {
            setState(.failed("Invalid signaling URL: \(urlString)"))
            return
        }

        if let manager, manager.socketURL == url, let socket, socket.status == .connected || socket.status == .connecting {
            log("Already \(socket.status) to \(url)")
            return
        }

        disconnect()

        var config: SocketIOClientConfiguration = [
            .log(false),
            .compress,
            .forceWebsockets(true),
            .reconnects(true),
            .reconnectAttempts(-1),
            .reconnectWait(1),
            .reconnectWaitMax(10),
            .handleQueue(DispatchQueue.main)
        ]
        if url.scheme == "wss" || url.scheme == "https" {
            config.insert(.secure(true))
        }

        let manager = SocketManager(socketURL: url, config: config)
        let socket = manager.defaultSocket
        self.manager = manager
        self.socket = socket

        installHandlers(on: socket)

        log("Connecting to \(url)")
        setState(.connecting)
        // The payload becomes `socket.handshake.auth` on the server and is
        // re-sent automatically by the manager on every reconnect.
        socket.connect(withPayload: ["token": token])
    }

    func disconnect() {
        guard manager != nil else { return }
        log("Disconnecting")
        socket?.removeAllHandlers()
        manager?.disconnect()
        socket = nil
        manager = nil
        registeredPhoneNumber = nil
        setState(.disconnected)
    }

    // MARK: Emits (client → server)

    func initiateCall(to phoneNumber: String, callId: String, hasVideo: Bool) {
        emit("call-initiate", ["to": phoneNumber, "callId": callId, "hasVideo": hasVideo])
    }

    func sendOffer(callId: String, sdp: String) {
        emit("offer", ["callId": callId, "sdp": sdp])
    }

    func sendAnswer(callId: String, sdp: String) {
        emit("answer", ["callId": callId, "sdp": sdp])
    }

    func sendIceCandidate(_ candidate: SignalingIceCandidate, callId: String) {
        emit("ice-candidate", ["callId": callId, "candidate": candidate.json])
    }

    func answerCall(callId: String) {
        emit("call-answer", ["callId": callId])
    }

    func rejectCall(callId: String, reason: String = "declined") {
        emit("call-reject", ["callId": callId, "reason": reason])
    }

    func endCall(callId: String) {
        emit("call-end", ["callId": callId])
    }

    private func emit(_ event: String, _ payload: [String: Any]) {
        guard let socket, socket.status == .connected else {
            log("Dropping '\(event)': socket not connected (\(socket?.status.description ?? "nil"))")
            return
        }
        if event != "ice-candidate" { log("→ \(event) \(summary(of: payload))") }
        socket.emit(event, payload)
    }

    // MARK: Handlers (server → client)

    private func installHandlers(on socket: SocketIOClient) {
        socket.on(clientEvent: .connect) { [weak self] _, _ in
            guard let self else { return }
            self.log("Connected; registering")
            self.setState(.connected)
            socket.emit("register")
        }

        socket.on(clientEvent: .disconnect) { [weak self] data, _ in
            guard let self else { return }
            self.log("Disconnected: \(data.first ?? "")")
            self.registeredPhoneNumber = nil
            // Keep .connecting while the manager is auto-reconnecting.
            if self.manager != nil {
                self.setState(.connecting)
            } else {
                self.setState(.disconnected)
            }
        }

        socket.on(clientEvent: .error) { [weak self] data, _ in
            guard let self else { return }
            let message = data.compactMap { ($0 as? String) ?? ($0 as? [String: Any])?["message"] as? String }.first
                ?? "\(data)"
            self.log("Error: \(message)")
            // The manager keeps retrying; surface the last error for the UI.
            self.setState(.failed(message))
        }

        socket.on(clientEvent: .reconnectAttempt) { [weak self] data, _ in
            self?.log("Reconnect attempt \(data.first ?? "")")
            self?.setState(.connecting)
        }

        socket.on("registered") { [weak self] data, _ in
            guard let self else { return }
            let dict = data.first as? [String: Any]
            self.registeredPhoneNumber = dict?["phoneNumber"] as? String
            self.log("Registered as \(self.registeredPhoneNumber ?? "?")")
            self.setState(.registered)
        }

        socket.on("incoming-call") { [weak self] data, _ in
            guard let self, let dict = data.first as? [String: Any],
                  let callId = dict["callId"] as? String,
                  let from = dict["from"] as? String else { return }
            let hasVideo = dict["hasVideo"] as? Bool ?? false
            self.log("← incoming-call \(callId) from \(from) video=\(hasVideo)")
            self.delegate?.signalingClient(self, didReceiveIncomingCall: SignalingIncomingCall(callId: callId, from: from, hasVideo: hasVideo))
        }

        socket.on("offer") { [weak self] data, _ in
            guard let self, let dict = data.first as? [String: Any],
                  let callId = dict["callId"] as? String,
                  let sdp = Self.sdpString(from: dict["sdp"]) else { return }
            self.log("← offer \(callId) (\(sdp.count) bytes)")
            self.delegate?.signalingClient(self, didReceiveOffer: sdp, callId: callId, from: dict["from"] as? String)
        }

        socket.on("answer") { [weak self] data, _ in
            guard let self, let dict = data.first as? [String: Any],
                  let callId = dict["callId"] as? String,
                  let sdp = Self.sdpString(from: dict["sdp"]) else { return }
            self.log("← answer \(callId) (\(sdp.count) bytes)")
            self.delegate?.signalingClient(self, didReceiveAnswer: sdp, callId: callId, from: dict["from"] as? String)
        }

        socket.on("ice-candidate") { [weak self] data, _ in
            guard let self, let dict = data.first as? [String: Any],
                  let callId = dict["callId"] as? String,
                  let candidate = SignalingIceCandidate(json: dict["candidate"]) else { return }
            self.delegate?.signalingClient(self, didReceiveIceCandidate: candidate, callId: callId)
        }

        socket.on("call-answered") { [weak self] data, _ in
            guard let self, let dict = data.first as? [String: Any],
                  let callId = dict["callId"] as? String else { return }
            self.log("← call-answered \(callId)")
            self.delegate?.signalingClient(self, callWasAnswered: callId, by: dict["by"] as? String)
        }

        socket.on("call-rejected") { [weak self] data, _ in
            guard let self, let dict = data.first as? [String: Any],
                  let callId = dict["callId"] as? String else { return }
            self.log("← call-rejected \(callId) reason=\(dict["reason"] ?? "")")
            self.delegate?.signalingClient(self, callWasRejected: callId, reason: dict["reason"] as? String)
        }

        socket.on("call-ended") { [weak self] data, _ in
            guard let self, let dict = data.first as? [String: Any],
                  let callId = dict["callId"] as? String else { return }
            self.log("← call-ended \(callId) reason=\(dict["reason"] ?? "")")
            self.delegate?.signalingClient(self, callDidEnd: callId, reason: dict["reason"] as? String)
        }

        socket.on("call-error") { [weak self] data, _ in
            guard let self else { return }
            let dict = data.first as? [String: Any]
            let message = dict?["error"] as? String ?? "Unknown signaling error"
            let callId = dict?["callId"] as? String
            self.log("← call-error \(callId ?? "-"): \(message)")
            self.delegate?.signalingClient(self, didReceiveCallError: message, callId: callId)
        }
    }

    // MARK: Helpers

    /// Accepts either a bare SDP string or a `{type, sdp}` dictionary.
    private static func sdpString(from value: Any?) -> String? {
        if let string = value as? String { return string }
        if let dict = value as? [String: Any] { return dict["sdp"] as? String }
        return nil
    }

    private func setState(_ newState: ConnectionState) {
        guard newState != state else { return }
        state = newState
        delegate?.signalingClient(self, didChangeState: newState)
    }

    private func summary(of payload: [String: Any]) -> String {
        payload.map { key, value in
            if let string = value as? String, string.count > 60 { return "\(key)=<\(string.count) chars>" }
            return "\(key)=\(value)"
        }.sorted().joined(separator: " ")
    }

    private func log(_ message: String) {
        print("📡 [Signaling] \(message)")
    }
}

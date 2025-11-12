# WebRTC Integration Guide

## Overview

WebRTC (Web Real-Time Communication) enables peer-to-peer audio and video communication. This document details how to integrate WebRTC into the iOS dialer application.

## WebRTC Library for iOS

### Google WebRTC SDK

The official Google WebRTC library is the recommended choice:

**Installation via CocoaPods:**
```ruby
pod 'GoogleWebRTC', '~> 1.1'
```

**Installation via Swift Package Manager:**
```
https://github.com/webrtc-sdk/Specs
```

**Why Google WebRTC:**
- Official implementation
- Actively maintained
- Comprehensive feature set
- Excellent iOS integration
- Hardware acceleration support
- Mature and battle-tested

## Core WebRTC Classes

### 1. RTCPeerConnectionFactory

The factory creates all WebRTC objects:

```swift
import WebRTC

class WebRTCClient {
    private let factory: RTCPeerConnectionFactory

    init() {
        // Initialize encoder/decoder factories
        let videoEncoderFactory = RTCDefaultVideoEncoderFactory()
        let videoDecoderFactory = RTCDefaultVideoDecoderFactory()

        // Create factory
        self.factory = RTCPeerConnectionFactory(
            encoderFactory: videoEncoderFactory,
            decoderFactory: videoDecoderFactory
        )
    }
}
```

### 2. RTCPeerConnection

Manages the peer-to-peer connection:

```swift
func createPeerConnection() -> RTCPeerConnection? {
    let config = RTCConfiguration()

    // Add STUN/TURN servers
    config.iceServers = [
        RTCIceServer(urlStrings: ["stun:stun.l.google.com:19302"]),
        RTCIceServer(
            urlStrings: ["turn:your-turn-server.com:3478"],
            username: "username",
            credential: "password"
        )
    ]

    // Connection settings
    config.sdpSemantics = .unifiedPlan
    config.continualGatheringPolicy = .gatherContinually

    let constraints = RTCMediaConstraints(
        mandatoryConstraints: nil,
        optionalConstraints: ["DtlsSrtpKeyAgreement": "true"]
    )

    let peerConnection = factory.peerConnection(
        with: config,
        constraints: constraints,
        delegate: self
    )

    return peerConnection
}
```

### 3. Media Tracks

#### Audio Track

```swift
func createAudioTrack() -> RTCAudioTrack {
    let constraints = RTCMediaConstraints(
        mandatoryConstraints: nil,
        optionalConstraints: nil
    )

    let audioSource = factory.audioSource(with: constraints)
    let audioTrack = factory.audioTrack(with: audioSource, trackId: "audio0")

    return audioTrack
}
```

#### Video Track

```swift
func createVideoTrack() -> RTCVideoTrack {
    let videoSource = factory.videoSource()

    // Configure video capture
    #if targetEnvironment(simulator)
    // Use file capturer for simulator
    #else
    if let capturer = RTCCameraVideoCapturer(delegate: videoSource) {
        startCapture(capturer: capturer)
    }
    #endif

    let videoTrack = factory.videoTrack(with: videoSource, trackId: "video0")

    return videoTrack
}

func startCapture(capturer: RTCCameraVideoCapturer) {
    guard let frontCamera = RTCCameraVideoCapturer.captureDevices()
        .first(where: { $0.position == .front }) else { return }

    let format = RTCCameraVideoCapturer.supportedFormats(for: frontCamera)
        .sorted { (f1, f2) -> Bool in
            let width1 = CMVideoFormatDescriptionGetDimensions(f1.formatDescription).width
            let width2 = CMVideoFormatDescriptionGetDimensions(f2.formatDescription).width
            return width1 < width2
        }.last

    guard let format = format else { return }

    let fps = format.videoSupportedFrameRateRanges.max { $0.maxFrameRate < $1.maxFrameRate }?.maxFrameRate ?? 30

    capturer.startCapture(
        with: frontCamera,
        format: format,
        fps: Int(fps)
    )
}
```

## WebRTC Connection Flow

### 1. Offer/Answer Exchange (SDP)

#### Creating an Offer (Caller)

```swift
func makeOffer(completion: @escaping (RTCSessionDescription) -> Void) {
    let constraints = RTCMediaConstraints(
        mandatoryConstraints: [
            "OfferToReceiveAudio": "true",
            "OfferToReceiveVideo": "true"
        ],
        optionalConstraints: nil
    )

    peerConnection.offer(for: constraints) { [weak self] sdp, error in
        guard let sdp = sdp, error == nil else {
            print("Error creating offer: \(error?.localizedDescription ?? "unknown")")
            return
        }

        self?.peerConnection.setLocalDescription(sdp) { error in
            if let error = error {
                print("Error setting local description: \(error.localizedDescription)")
                return
            }

            completion(sdp)
        }
    }
}
```

#### Creating an Answer (Callee)

```swift
func makeAnswer(completion: @escaping (RTCSessionDescription) -> Void) {
    let constraints = RTCMediaConstraints(
        mandatoryConstraints: [
            "OfferToReceiveAudio": "true",
            "OfferToReceiveVideo": "true"
        ],
        optionalConstraints: nil
    )

    peerConnection.answer(for: constraints) { [weak self] sdp, error in
        guard let sdp = sdp, error == nil else {
            print("Error creating answer: \(error?.localizedDescription ?? "unknown")")
            return
        }

        self?.peerConnection.setLocalDescription(sdp) { error in
            if let error = error {
                print("Error setting local description: \(error.localizedDescription)")
                return
            }

            completion(sdp)
        }
    }
}
```

#### Setting Remote Description

```swift
func handleRemoteDescription(_ sdp: RTCSessionDescription) {
    peerConnection.setRemoteDescription(sdp) { error in
        if let error = error {
            print("Error setting remote description: \(error.localizedDescription)")
            return
        }

        // If we received an offer, create an answer
        if sdp.type == .offer {
            self.makeAnswer { answer in
                // Send answer to remote peer via signaling
            }
        }
    }
}
```

### 2. ICE Candidate Exchange

```swift
extension WebRTCClient: RTCPeerConnectionDelegate {
    func peerConnection(_ peerConnection: RTCPeerConnection,
                       didGenerate candidate: RTCIceCandidate) {
        // Send this candidate to the remote peer via signaling
        let candidateDict: [String: Any] = [
            "candidate": candidate.sdp,
            "sdpMLineIndex": candidate.sdpMLineIndex,
            "sdpMid": candidate.sdpMid ?? ""
        ]

        signalingClient.send(iceCandidate: candidateDict)
    }

    func handleRemoteCandidate(_ candidate: RTCIceCandidate) {
        peerConnection.add(candidate) { error in
            if let error = error {
                print("Error adding ICE candidate: \(error.localizedDescription)")
            }
        }
    }
}
```

### 3. Connection State Changes

```swift
extension WebRTCClient: RTCPeerConnectionDelegate {
    func peerConnection(_ peerConnection: RTCPeerConnection,
                       didChange state: RTCIceConnectionState) {
        switch state {
        case .connected:
            print("Peer connected!")
            // Update UI to show connected state

        case .disconnected:
            print("Peer disconnected")
            // Handle reconnection logic

        case .failed:
            print("Connection failed")
            // End call, show error

        case .closed:
            print("Connection closed")
            // Clean up resources

        default:
            break
        }
    }

    func peerConnection(_ peerConnection: RTCPeerConnection,
                       didChange state: RTCPeerConnectionState) {
        print("Peer connection state: \(state)")
    }
}
```

### 4. Media Stream Handling

```swift
extension WebRTCClient: RTCPeerConnectionDelegate {
    func peerConnection(_ peerConnection: RTCPeerConnection,
                       didAdd stream: RTCMediaStream) {
        print("Stream added with \(stream.audioTracks.count) audio tracks and \(stream.videoTracks.count) video tracks")

        // Handle remote video track
        if let videoTrack = stream.videoTracks.first {
            self.remoteVideoTrack = videoTrack
            // Attach to video renderer (UI)
        }

        // Remote audio is automatically played
    }

    func peerConnection(_ peerConnection: RTCPeerConnection,
                       didRemove stream: RTCMediaStream) {
        print("Stream removed")
        self.remoteVideoTrack = nil
    }
}
```

## Video Rendering

### Local Video Preview

```swift
import WebRTC

class LocalVideoView: UIView {
    private let videoView: RTCMTLVideoView

    override init(frame: CGRect) {
        self.videoView = RTCMTLVideoView(frame: frame)
        super.init(frame: frame)

        videoView.contentMode = .scaleAspectFill
        addSubview(videoView)
    }

    func renderTrack(_ track: RTCVideoTrack) {
        track.add(videoView)
    }
}
```

### Remote Video View

```swift
class RemoteVideoView: UIView {
    private let videoView: RTCMTLVideoView

    override init(frame: CGRect) {
        self.videoView = RTCMTLVideoView(frame: frame)
        super.init(frame: frame)

        videoView.contentMode = .scaleAspectFit
        addSubview(videoView)
    }

    func renderTrack(_ track: RTCVideoTrack) {
        track.add(videoView)
    }
}
```

## Audio Session Configuration

```swift
import AVFoundation

func configureAudioSession() {
    let audioSession = RTCAudioSession.sharedInstance()

    audioSession.lockForConfiguration()
    defer { audioSession.unlockForConfiguration() }

    do {
        try audioSession.setCategory(AVAudioSession.Category.playAndRecord.rawValue)
        try audioSession.setMode(AVAudioSession.Mode.voiceChat.rawValue)
        try audioSession.overrideOutputAudioPort(.none)
    } catch {
        print("Error configuring audio session: \(error)")
    }
}

func setSpeakerPhone(enabled: Bool) {
    let audioSession = RTCAudioSession.sharedInstance()

    audioSession.lockForConfiguration()
    defer { audioSession.unlockForConfiguration() }

    do {
        if enabled {
            try audioSession.overrideOutputAudioPort(.speaker)
        } else {
            try audioSession.overrideOutputAudioPort(.none)
        }
    } catch {
        print("Error setting speaker: \(error)")
    }
}
```

## Complete WebRTC Client Example

```swift
import WebRTC

protocol WebRTCClientDelegate: AnyObject {
    func webRTCClient(_ client: WebRTCClient, didReceiveRemoteVideoTrack track: RTCVideoTrack)
    func webRTCClient(_ client: WebRTCClient, didChangeConnectionState state: RTCIceConnectionState)
}

class WebRTCClient: NSObject {

    // MARK: - Properties

    private let factory: RTCPeerConnectionFactory
    private var peerConnection: RTCPeerConnection?
    private var localVideoTrack: RTCVideoTrack?
    private var localAudioTrack: RTCAudioTrack?
    private var videoCapturer: RTCCameraVideoCapturer?

    weak var delegate: WebRTCClientDelegate?

    // MARK: - Initialization

    override init() {
        RTCInitializeSSL()

        let videoEncoderFactory = RTCDefaultVideoEncoderFactory()
        let videoDecoderFactory = RTCDefaultVideoDecoderFactory()

        self.factory = RTCPeerConnectionFactory(
            encoderFactory: videoEncoderFactory,
            decoderFactory: videoDecoderFactory
        )

        super.init()
    }

    deinit {
        RTCCleanupSSL()
    }

    // MARK: - Public Methods

    func setupPeerConnection() {
        let config = RTCConfiguration()
        config.iceServers = [
            RTCIceServer(urlStrings: ["stun:stun.l.google.com:19302"])
        ]
        config.sdpSemantics = .unifiedPlan

        let constraints = RTCMediaConstraints(
            mandatoryConstraints: nil,
            optionalConstraints: ["DtlsSrtpKeyAgreement": "true"]
        )

        self.peerConnection = factory.peerConnection(
            with: config,
            constraints: constraints,
            delegate: self
        )
    }

    func startLocalMedia(isVideoCall: Bool) {
        // Audio track (always needed)
        self.localAudioTrack = createAudioTrack()
        if let audioTrack = localAudioTrack {
            peerConnection?.add(audioTrack, streamIds: ["stream0"])
        }

        // Video track (only for video calls)
        if isVideoCall {
            self.localVideoTrack = createVideoTrack()
            if let videoTrack = localVideoTrack {
                peerConnection?.add(videoTrack, streamIds: ["stream0"])
            }
        }
    }

    func muteAudio(_ mute: Bool) {
        localAudioTrack?.isEnabled = !mute
    }

    func muteVideo(_ mute: Bool) {
        localVideoTrack?.isEnabled = !mute
    }

    func close() {
        peerConnection?.close()
        peerConnection = nil
    }

    // MARK: - Private Methods

    private func createAudioTrack() -> RTCAudioTrack {
        let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        let audioSource = factory.audioSource(with: constraints)
        return factory.audioTrack(with: audioSource, trackId: "audio0")
    }

    private func createVideoTrack() -> RTCVideoTrack {
        let videoSource = factory.videoSource()
        let videoCapturer = RTCCameraVideoCapturer(delegate: videoSource)
        self.videoCapturer = videoCapturer

        startVideoCapture()

        return factory.videoTrack(with: videoSource, trackId: "video0")
    }

    private func startVideoCapture() {
        guard let capturer = videoCapturer,
              let frontCamera = RTCCameraVideoCapturer.captureDevices()
                .first(where: { $0.position == .front }),
              let format = RTCCameraVideoCapturer.supportedFormats(for: frontCamera).last
        else { return }

        let fps = format.videoSupportedFrameRateRanges.max { $0.maxFrameRate < $1.maxFrameRate }?.maxFrameRate ?? 30

        capturer.startCapture(with: frontCamera, format: format, fps: Int(fps))
    }
}

// MARK: - RTCPeerConnectionDelegate

extension WebRTCClient: RTCPeerConnectionDelegate {
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange state: RTCSignalingState) {
        print("Signaling state: \(state)")
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {
        if let videoTrack = stream.videoTracks.first {
            delegate?.webRTCClient(self, didReceiveRemoteVideoTrack: videoTrack)
        }
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {
        print("Stream removed")
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange state: RTCIceConnectionState) {
        delegate?.webRTCClient(self, didChangeConnectionState: state)
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange state: RTCIceGatheringState) {
        print("ICE gathering state: \(state)")
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        // Send to signaling server
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {
        print("Candidates removed")
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {
        print("Data channel opened")
    }

    func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {
        print("Should negotiate")
    }
}
```

## Best Practices

### 1. Connection Quality Monitoring

```swift
func monitorConnectionQuality() {
    peerConnection?.statistics { report in
        report.statistics.forEach { (key, stats) in
            if stats.type == "inbound-rtp" {
                if let packetsLost = stats.values["packetsLost"] as? NSNumber {
                    print("Packets lost: \(packetsLost)")
                }
            }
        }
    }
}
```

### 2. Adaptive Bitrate

WebRTC handles this automatically, but you can configure:

```swift
let constraints = RTCMediaConstraints(
    mandatoryConstraints: [
        "maxBitrate": "2000000"  // 2 Mbps
    ],
    optionalConstraints: nil
)
```

### 3. Network Change Handling

```swift
import Network

class NetworkMonitor {
    let monitor = NWPathMonitor()

    func startMonitoring() {
        monitor.pathUpdateHandler = { path in
            if path.status == .satisfied {
                // Network available
            } else {
                // Network unavailable - handle reconnection
            }
        }

        monitor.start(queue: DispatchQueue.global(qos: .background))
    }
}
```

### 4. Memory Management

- Always remove video tracks from renderers when done
- Close peer connections properly
- Release media tracks
- Clean up on app background

### 5. Error Handling

Always handle errors gracefully:

```swift
func createOffer() {
    peerConnection?.offer(for: constraints) { sdp, error in
        if let error = error {
            // Show user-friendly error
            // Log for debugging
            // Attempt recovery if possible
            return
        }

        guard let sdp = sdp else { return }
        // Continue with SDP
    }
}
```

## Performance Optimization

1. **Use hardware acceleration**: Enabled by default with RTCDefaultVideoEncoder/DecoderFactory
2. **Proper frame rates**: Don't exceed 30 fps for mobile
3. **Resolution**: Start with 640x480, scale based on network
4. **Background handling**: Pause video capture when app backgrounds
5. **Battery optimization**: Disable video when not needed

## Troubleshooting

### No Audio/Video

- Check permissions (camera/microphone)
- Verify audio session configuration
- Check if tracks are added to peer connection
- Verify STUN/TURN servers are reachable

### Connection Failures

- Check ICE candidate gathering
- Verify TURN server credentials
- Check firewall/NAT configuration
- Monitor ICE connection state changes

### Poor Quality

- Check network bandwidth
- Monitor packet loss
- Verify codec support
- Check CPU usage

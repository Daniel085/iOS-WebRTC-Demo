//
//  EngineAudioDevice.swift
//  WebRTCDialer
//
//  A WebRTC audio device (`RTCAudioDevice`) built on AVAudioEngine.
//
//  WebRTC's default audio device owns the voice-processing audio unit, so the
//  app cannot see the microphone audio it sends. This device replaces it: the
//  engine's voice-processed input is converted to 16-bit PCM and handed to
//  WebRTC, and the engine's output pulls decoded remote audio from WebRTC.
//  Because the app owns the engine, it can also tap the processed microphone
//  signal for on-device transcription (`setCaptureHandler`).
//
//  Threading: WebRTC calls the RTCAudioDevice methods on its own worker
//  thread; CallKit hand-offs arrive on the main thread. State changes are
//  serialized with `lock`. The two render callbacks run on the real-time I/O
//  thread and only touch preallocated buffers and atomics.
//

import Foundation
import AVFoundation
import Synchronization
@preconcurrency import WebRTC

nonisolated final class EngineAudioDevice: NSObject, RTCAudioDevice, @unchecked Sendable {

    static let shared = EngineAudioDevice()

    /// Called with each voice-processed microphone buffer (about 100 ms) on a
    /// background thread, while capture is running.
    typealias CaptureHandler = @Sendable (AVAudioPCMBuffer) -> Void

    // MARK: State (guarded by `lock`)

    private let lock = NSRecursiveLock()
    private var delegate: RTCAudioDeviceDelegate?
    private var engine: AVAudioEngine?
    private var inputFormat: AVAudioFormat?
    private var sessionActive = false
    private var playoutInitialized = false
    private var recordingInitialized = false
    private var playoutRequested = false
    private var recordingRequested = false
    private var captureHandler: CaptureHandler?
    private var tapInstalled = false
    private var configurationObserver: NSObjectProtocol?
    private var reportedSampleRate: Double = 0

    // MARK: Real-time state

    /// Read on the I/O thread; written under `lock` before/after the engine runs.
    private nonisolated(unsafe) var deliverRecordedData: RTCAudioDeviceDeliverRecordedDataBlock?
    private nonisolated(unsafe) var getPlayoutData: RTCAudioDeviceGetPlayoutDataBlock?
    private let isPlayingFlag = Atomic<Bool>(false)
    private let isRecordingFlag = Atomic<Bool>(false)

    private let maxFrames = 8192
    private let recordScratch: UnsafeMutablePointer<Int16>
    private let playoutScratch: UnsafeMutablePointer<Int16>

    private override init() {
        recordScratch = .allocate(capacity: maxFrames)
        recordScratch.initialize(repeating: 0, count: maxFrames)
        playoutScratch = .allocate(capacity: maxFrames)
        playoutScratch.initialize(repeating: 0, count: maxFrames)
        super.init()
    }

    // MARK: App-facing controls

    /// CallKit activated/deactivated the audio session (or the app did, when
    /// CallKit is not in use). The engine only runs while the session is active.
    func setAudioSessionActive(_ active: Bool) {
        lock.withLock {
            sessionActive = active
            log("Audio session \(active ? "active" : "inactive")")
            updateEngine()
        }
    }

    /// Install (or remove, with nil) the microphone tap used for transcription.
    func setCaptureHandler(_ handler: CaptureHandler?) {
        lock.withLock {
            captureHandler = handler
            updateTap()
        }
    }

    /// Whether microphone buffers can currently be captured.
    var isCapturing: Bool {
        lock.withLock { engine != nil && tapInstalled }
    }

    /// The simulator's voice-processing unit can deadlock CoreAudio, so the
    /// engine only starts there when `simulatorAudioEnabled` is set, and then
    /// without voice processing (see WebRTCClient.initialize).
    private var engineAllowed: Bool {
        #if targetEnvironment(simulator)
        return UserDefaults.standard.bool(forKey: Constants.UserDefaults.simulatorAudioEnabled)
        #else
        return true
        #endif
    }

    // MARK: RTCAudioDevice: parameters

    private var session: AVAudioSession { AVAudioSession.sharedInstance() }

    private var currentSampleRate: Double {
        lock.withLock {
            if let rate = inputFormat?.sampleRate, rate > 0 { return rate }
            let rate = session.sampleRate
            return rate > 0 ? rate : 48_000
        }
    }

    var deviceInputSampleRate: Double { currentSampleRate }
    var inputIOBufferDuration: TimeInterval { session.ioBufferDuration }
    var inputNumberOfChannels: Int { 1 }
    var inputLatency: TimeInterval { session.inputLatency }
    var deviceOutputSampleRate: Double { currentSampleRate }
    var outputIOBufferDuration: TimeInterval { session.ioBufferDuration }
    var outputNumberOfChannels: Int { 1 }
    var outputLatency: TimeInterval { session.outputLatency }

    // MARK: RTCAudioDevice: lifecycle

    var isInitialized: Bool { lock.withLock { delegate != nil } }

    func initialize(with delegate: RTCAudioDeviceDelegate) -> Bool {
        lock.withLock {
            self.delegate = delegate
            deliverRecordedData = delegate.deliverRecordedData
            getPlayoutData = delegate.getPlayoutData
            log("Initialized")
            return true
        }
    }

    func terminateDevice() -> Bool {
        lock.withLock {
            playoutRequested = false
            recordingRequested = false
            playoutInitialized = false
            recordingInitialized = false
            stopEngine()
            deliverRecordedData = nil
            getPlayoutData = nil
            delegate = nil
            log("Terminated")
            return true
        }
    }

    var isPlayoutInitialized: Bool { lock.withLock { playoutInitialized } }

    func initializePlayout() -> Bool {
        lock.withLock { playoutInitialized = true; return true }
    }

    var isPlaying: Bool { lock.withLock { playoutRequested } }

    func startPlayout() -> Bool {
        lock.withLock {
            playoutRequested = true
            isPlayingFlag.store(true, ordering: .relaxed)
            updateEngine()
            return true
        }
    }

    func stopPlayout() -> Bool {
        lock.withLock {
            playoutRequested = false
            isPlayingFlag.store(false, ordering: .relaxed)
            updateEngine()
            return true
        }
    }

    var isRecordingInitialized: Bool { lock.withLock { recordingInitialized } }

    func initializeRecording() -> Bool {
        lock.withLock { recordingInitialized = true; return true }
    }

    var isRecording: Bool { lock.withLock { recordingRequested } }

    func startRecording() -> Bool {
        lock.withLock {
            recordingRequested = true
            isRecordingFlag.store(true, ordering: .relaxed)
            updateEngine()
            return true
        }
    }

    func stopRecording() -> Bool {
        lock.withLock {
            recordingRequested = false
            isRecordingFlag.store(false, ordering: .relaxed)
            updateEngine()
            return true
        }
    }

    // MARK: Engine management (call with `lock` held)

    private func updateEngine() {
        let shouldRun = (playoutRequested || recordingRequested) && sessionActive && engineAllowed
        if shouldRun, engine == nil {
            startEngine()
        } else if !shouldRun, engine != nil {
            stopEngine()
        }
    }

    private func startEngine() {
        let engine = AVAudioEngine()
        let input = engine.inputNode

        #if !targetEnvironment(simulator)
        do {
            // Echo cancellation, noise suppression and AGC, like WebRTC's own unit.
            try input.setVoiceProcessingEnabled(true)
        } catch {
            log("Voice processing unavailable: \(error.localizedDescription)")
        }
        #endif

        let hardwareInput = input.outputFormat(forBus: 0)
        let hasInput = hardwareInput.sampleRate > 0 && hardwareInput.channelCount > 0
        let sampleRate = hasInput ? hardwareInput.sampleRate : (session.sampleRate > 0 ? session.sampleRate : 48_000)
        guard let monoFloat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false) else {
            log("Could not create the playout format")
            return
        }

        // Playout: WebRTC → speaker.
        let source = AVAudioSourceNode(format: monoFloat) { [unowned self] isSilence, timestamp, frameCount, outputData in
            self.renderPlayout(isSilence: isSilence, timestamp: timestamp, frameCount: frameCount, outputData: outputData)
        }
        engine.attach(source)
        engine.connect(source, to: engine.mainMixerNode, format: monoFloat)

        // Recording: microphone → WebRTC.
        if hasInput {
            let sink = AVAudioSinkNode { [unowned self] timestamp, frameCount, inputData in
                self.deliverRecording(timestamp: timestamp, frameCount: frameCount, inputData: inputData)
            }
            engine.attach(sink)
            engine.connect(input, to: sink, format: hardwareInput)
            inputFormat = hardwareInput
        } else {
            log("No microphone input available (permission denied?); sending no audio")
            inputFormat = monoFloat
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            log("Engine start failed: \(error.localizedDescription)")
            inputFormat = nil
            return
        }
        self.engine = engine
        log("Engine started at \(Int(sampleRate)) Hz, input \(hardwareInput.channelCount) ch")

        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil
        ) { [weak self] _ in
            self?.restartAfterConfigurationChange()
        }

        updateTap()
        notifyParametersIfChanged(sampleRate)
    }

    private func stopEngine() {
        guard let engine else { return }
        if let configurationObserver {
            NotificationCenter.default.removeObserver(configurationObserver)
        }
        configurationObserver = nil
        if tapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        engine.stop()
        self.engine = nil
        inputFormat = nil
        log("Engine stopped")
    }

    /// Route changes (headphones, Bluetooth, speaker) can change the hardware
    /// format; rebuild the graph so the formats stay consistent.
    private func restartAfterConfigurationChange() {
        lock.withLock {
            guard engine != nil else { return }
            log("Engine configuration changed; restarting")
            stopEngine()
            updateEngine()
        }
    }

    private func notifyParametersIfChanged(_ sampleRate: Double) {
        guard sampleRate != reportedSampleRate else { return }
        let first = reportedSampleRate == 0
        reportedSampleRate = sampleRate
        guard !first, let delegate else { return }
        delegate.notifyAudioInputParametersChange()
        delegate.notifyAudioOutputParametersChange()
    }

    private func updateTap() {
        guard let engine, let inputFormat, inputFormat.sampleRate > 0 else { return }
        let input = engine.inputNode
        if let handler = captureHandler, !tapInstalled {
            input.installTap(onBus: 0, bufferSize: 4096, format: input.outputFormat(forBus: 0)) { buffer, _ in
                handler(buffer)
            }
            tapInstalled = true
            log("Capture tap installed")
        } else if captureHandler == nil, tapInstalled {
            input.removeTap(onBus: 0)
            tapInstalled = false
            log("Capture tap removed")
        }
    }

    // MARK: Real-time callbacks

    private func renderPlayout(
        isSilence: UnsafeMutablePointer<ObjCBool>,
        timestamp: UnsafePointer<AudioTimeStamp>,
        frameCount: AVAudioFrameCount,
        outputData: UnsafeMutablePointer<AudioBufferList>
    ) -> OSStatus {
        let frames = Int(frameCount)
        let output = UnsafeMutableAudioBufferListPointer(outputData)
        guard isPlayingFlag.load(ordering: .relaxed), let getPlayoutData, frames <= maxFrames else {
            for buffer in output { if let data = buffer.mData { memset(data, 0, Int(buffer.mDataByteSize)) } }
            isSilence.pointee = true
            return noErr
        }

        var flags = AudioUnitRenderActionFlags()
        var pcm = AudioBufferList(
            mNumberBuffers: 1,
            mBuffers: AudioBuffer(mNumberChannels: 1, mDataByteSize: UInt32(frames * 2), mData: playoutScratch)
        )
        let status = getPlayoutData(&flags, timestamp, 0, frameCount, &pcm)
        if status != noErr { memset(playoutScratch, 0, frames * 2) }

        let scale: Float = 1.0 / 32768.0
        for buffer in output {
            guard let samples = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
            for i in 0..<frames { samples[i] = Float(playoutScratch[i]) * scale }
        }
        return noErr
    }

    private func deliverRecording(
        timestamp: UnsafePointer<AudioTimeStamp>,
        frameCount: AVAudioFrameCount,
        inputData: UnsafePointer<AudioBufferList>
    ) -> OSStatus {
        let frames = Int(frameCount)
        guard isRecordingFlag.load(ordering: .relaxed), let deliverRecordedData, frames <= maxFrames else { return noErr }
        let input = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inputData))
        guard input.count > 0, let samples = input[0].mData?.assumingMemoryBound(to: Float.self) else { return noErr }

        for i in 0..<frames {
            let clamped = max(-1, min(1, samples[i]))
            recordScratch[i] = Int16(clamped * 32767)
        }
        var flags = AudioUnitRenderActionFlags()
        var pcm = AudioBufferList(
            mNumberBuffers: 1,
            mBuffers: AudioBuffer(mNumberChannels: 1, mDataByteSize: UInt32(frames * 2), mData: recordScratch)
        )
        return deliverRecordedData(&flags, timestamp, 1, frameCount, &pcm, nil, nil)
    }

    private func log(_ message: String) {
        print("🎙️ [AudioDevice] \(message)")
    }
}

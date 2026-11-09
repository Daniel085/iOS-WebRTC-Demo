//
//  DemoSpeechSource.swift
//  WebRTCDialer
//
//  Test audio for transcription. The simulator runs calls with the audio unit
//  off (it can deadlock CoreAudio), so there is no microphone signal to
//  transcribe. This source speaks one side of a short scripted conversation
//  with AVSpeechSynthesizer and feeds the audio, paced in real time, to the
//  same handler the microphone tap would use. The real recognizer then
//  transcribes it, so captions, consent, exchange and summaries can all be
//  exercised on two simulators.
//
//  Enabled automatically in the simulator unless `simulatorAudioEnabled` is
//  set, and on a device with the `transcriptionDemoAudio` default.
//

import Foundation
import AVFoundation

nonisolated final class DemoSpeechSource: @unchecked Sendable {

    enum Role { case caller, callee }

    /// A two-sided script. Each phone speaks its own lines and stays quiet
    /// (sending silence) for roughly as long as the other side's lines take.
    static let script: [(Role, String)] = [
        (.caller, "Hi Sam, thanks for taking my call. I wanted to go over the kitchen remodel estimate."),
        (.callee, "Of course. We have you scheduled for Thursday at ten in the morning to measure the cabinets."),
        (.caller, "Thursday works for me. Could you send me the revised quote before then?"),
        (.callee, "Yes, I will email the updated quote by Wednesday afternoon."),
        (.caller, "Great. I will make sure someone is home to let your team in."),
        (.callee, "Perfect. See you on Thursday.")
    ]

    static var isEnabled: Bool {
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: Constants.UserDefaults.transcriptionDemoAudio) { return true }
        #if targetEnvironment(simulator)
        return !defaults.bool(forKey: Constants.UserDefaults.simulatorAudioEnabled)
        #else
        return false
        #endif
    }

    private let synthesizer = AVSpeechSynthesizer()
    private var task: Task<Void, Never>?

    func start(role: Role, handler: @escaping @Sendable (AVAudioPCMBuffer) -> Void) {
        stop()
        let synthesizer = self.synthesizer
        task = Task.detached {
            var silenceFormat: AVAudioFormat?
            for (speaker, line) in Self.script {
                if Task.isCancelled { return }
                if speaker == role {
                    let buffers = await Self.synthesize(line, with: synthesizer)
                    silenceFormat = silenceFormat ?? buffers.first?.format
                    for buffer in buffers {
                        if Task.isCancelled { return }
                        handler(buffer)
                        try? await Task.sleep(for: .seconds(Double(buffer.frameLength) / buffer.format.sampleRate))
                    }
                } else {
                    // About 14 characters per second of speech, plus a pause.
                    let estimate = Double(line.count) / 14.0
                    await Self.sendSilence(seconds: estimate, format: silenceFormat, handler: handler)
                }
                await Self.sendSilence(seconds: 1.0, format: silenceFormat, handler: handler)
            }
            print("📝 [DemoAudio] Script finished")
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        synthesizer.stopSpeaking(at: .immediate)
    }

    // MARK: Helpers

    private static func synthesize(_ text: String, with synthesizer: AVSpeechSynthesizer) async -> [AVAudioPCMBuffer] {
        final class Collector: @unchecked Sendable {
            var buffers: [AVAudioPCMBuffer] = []
            var finished = false
        }
        let collector = Collector()
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        return await withCheckedContinuation { continuation in
            synthesizer.write(utterance) { buffer in
                guard !collector.finished else { return }
                guard let pcm = buffer as? AVAudioPCMBuffer, pcm.frameLength > 0 else {
                    collector.finished = true
                    continuation.resume(returning: collector.buffers)
                    return
                }
                if let copy = pcm.copy() as? AVAudioPCMBuffer { collector.buffers.append(copy) }
            }
        }
    }

    /// Silence keeps the recognizer's clock running so it finalizes phrases.
    private static func sendSilence(seconds: Double, format: AVAudioFormat?, handler: @Sendable (AVAudioPCMBuffer) -> Void) async {
        let format = format ?? AVAudioFormat(standardFormatWithSampleRate: 22_050, channels: 1)!
        let chunk = 0.1
        var remaining = seconds
        while remaining > 0, !Task.isCancelled {
            let frames = AVAudioFrameCount(format.sampleRate * min(chunk, remaining))
            if let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) {
                buffer.frameLength = frames
                for audio in UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList) {
                    if let data = audio.mData { memset(data, 0, Int(audio.mDataByteSize)) }
                }
                handler(buffer)
            }
            try? await Task.sleep(for: .seconds(chunk))
            remaining -= chunk
        }
    }
}

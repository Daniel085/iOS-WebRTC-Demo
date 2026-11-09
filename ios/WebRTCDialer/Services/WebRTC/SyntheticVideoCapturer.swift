//
//  SyntheticVideoCapturer.swift
//  WebRTCDialer
//
//  Stand-in for RTCCameraVideoCapturer where no camera exists (the iOS
//  simulator). Generates a scrolling colour-bar test pattern so a video track
//  negotiates, encodes and renders exactly like a camera track would.
//

import Foundation
import CoreVideo
@preconcurrency import WebRTC

@MainActor
final class SyntheticVideoCapturer: RTCVideoCapturer {

    /// Two visibly different patterns so "flip camera" has an effect.
    enum Pattern {
        case front   // saturated colour bars
        case back    // grey ramp
    }

    var pattern: Pattern = .front

    private let width = 640
    private let height = 480
    private let fps = 15

    private var timer: Timer?
    private var frameIndex = 0
    private var pool: CVPixelBufferPool?

    func start() {
        guard timer == nil else { return }
        var pool: CVPixelBufferPool?
        let attributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ]
        CVPixelBufferPoolCreate(nil, nil, attributes as CFDictionary, &pool)
        self.pool = pool
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / Double(fps), repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.emitFrame() }
        }
        print("🎥 [SyntheticVideo] Started \(width)x\(height)@\(fps)")
    }

    func stop() {
        guard timer != nil else { return }
        timer?.invalidate()
        timer = nil
        pool = nil
        print("🎥 [SyntheticVideo] Stopped after \(frameIndex) frames")
    }

    private func emitFrame() {
        guard let pool else { return }
        var pixelBuffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pixelBuffer)
        guard let pixelBuffer else { return }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        if let base = CVPixelBufferGetBaseAddress(pixelBuffer) {
            let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
            fill(base: base, bytesPerRow: bytesPerRow)
        }
        CVPixelBufferUnlockBaseAddress(pixelBuffer, [])

        let buffer = RTCCVPixelBuffer(pixelBuffer: pixelBuffer)
        let timeStampNs = Int64(Date().timeIntervalSince1970 * 1_000_000_000)
        let frame = RTCVideoFrame(buffer: buffer, rotation: ._0, timeStampNs: timeStampNs)
        delegate?.capturer(self, didCapture: frame)
        frameIndex += 1
    }

    /// BGRA colour bars scrolling left, plus a white stripe moving down.
    private func fill(base: UnsafeMutableRawPointer, bytesPerRow: Int) {
        let bars: [UInt32]
        switch pattern {
        case .front:
            bars = [0xFFFFFFFF, 0xFFFFFF00, 0xFF00FFFF, 0xFF00FF00, 0xFFFF00FF, 0xFFFF0000, 0xFF0000FF, 0xFF202020]
        case .back:
            bars = [0xFF202020, 0xFF404040, 0xFF606060, 0xFF808080, 0xFFA0A0A0, 0xFFC0C0C0, 0xFFE0E0E0, 0xFFFFFFFF]
        }
        let barWidth = width / bars.count
        let scroll = (frameIndex * 4) % width

        // One template row, copied into every scan line.
        var row = [UInt32](repeating: 0, count: width)
        for x in 0..<width {
            let index = ((x + scroll) / barWidth) % bars.count
            row[x] = bars[index]
        }
        let stripeTop = (frameIndex * 3) % height
        let stripeBottom = min(stripeTop + 24, height)
        let white = [UInt32](repeating: 0xFFFFFFFF, count: width)

        row.withUnsafeBytes { rowBytes in
            white.withUnsafeBytes { whiteBytes in
                for y in 0..<height {
                    let destination = base.advanced(by: y * bytesPerRow)
                    let source = (y >= stripeTop && y < stripeBottom) ? whiteBytes : rowBytes
                    destination.copyMemory(from: source.baseAddress!, byteCount: width * 4)
                }
            }
        }
    }
}

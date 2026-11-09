//
//  VideoView.swift
//  WebRTCDialer
//
//  SwiftUI wrapper around RTCMTLVideoView that renders an RTCVideoTrack.
//

import SwiftUI
import UIKit
@preconcurrency import WebRTC

struct VideoView: UIViewRepresentable {
    let track: RTCVideoTrack?
    var contentMode: UIView.ContentMode = .scaleAspectFill
    /// Mirror horizontally (front-camera self view).
    var mirrored: Bool = false

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> RTCMTLVideoView {
        let view = RTCMTLVideoView(frame: .zero)
        view.videoContentMode = contentMode
        view.backgroundColor = .black
        view.clipsToBounds = true
        return view
    }

    func updateUIView(_ view: RTCMTLVideoView, context: Context) {
        view.videoContentMode = contentMode
        view.transform = mirrored ? CGAffineTransform(scaleX: -1, y: 1) : .identity
        // Track wrappers are not unique per native track; compare by id.
        guard context.coordinator.track?.trackId != track?.trackId else { return }
        context.coordinator.track?.remove(view)
        track?.add(view)
        context.coordinator.track = track
    }

    static func dismantleUIView(_ view: RTCMTLVideoView, coordinator: Coordinator) {
        coordinator.track?.remove(view)
        coordinator.track = nil
    }

    final class Coordinator {
        var track: RTCVideoTrack?
    }
}

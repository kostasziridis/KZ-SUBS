import AVFoundation
import SwiftUI
import UIKit

/// Hosts an `AVPlayerLayer` directly.
///
/// Preferred over `AVKit`'s `VideoPlayer` because later phases draw captions and a
/// custom timeline over the video, and need full control of the transport.
struct PlayerLayerView: UIViewRepresentable {

    let player: AVPlayer
    var videoGravity: AVLayerVideoGravity = .resizeAspect

    func makeUIView(context: Context) -> PlayerHostingView {
        let view = PlayerHostingView()
        view.backgroundColor = .black
        view.playerLayer.videoGravity = videoGravity
        view.playerLayer.player = player
        return view
    }

    func updateUIView(_ uiView: PlayerHostingView, context: Context) {
        // Never swap the player unless it genuinely changed: reassigning restarts rendering.
        if uiView.playerLayer.player !== player {
            uiView.playerLayer.player = player
        }
        if uiView.playerLayer.videoGravity != videoGravity {
            uiView.playerLayer.videoGravity = videoGravity
        }
    }
}

/// A `UIView` whose backing layer *is* the player layer, so it resizes with the view
/// instead of needing manual frame bookkeeping.
final class PlayerHostingView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }

    var playerLayer: AVPlayerLayer {
        // Safe by construction: `layerClass` above guarantees the type.
        layer as! AVPlayerLayer
    }
}

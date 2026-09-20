import Foundation
import CoreGraphics

/// A video the user picked, already copied into storage the app controls.
///
/// Sizes here are *display* sizes: the natural size with the track's preferred
/// transform applied, so a portrait clip reports 1080 x 1920 and not 1920 x 1080.
struct VideoAsset: Identifiable, Hashable, Sendable {
    let id: UUID
    /// File inside the app's own container. The original Photos asset is never touched.
    var url: URL
    var filename: String
    var duration: TimeInterval
    var pixelSize: CGSize
    var frameRate: Double
    var hasAudio: Bool
    var thumbnailURL: URL?

    init(
        id: UUID = UUID(),
        url: URL,
        filename: String,
        duration: TimeInterval,
        pixelSize: CGSize,
        frameRate: Double,
        hasAudio: Bool,
        thumbnailURL: URL? = nil
    ) {
        self.id = id
        self.url = url
        self.filename = filename
        self.duration = duration
        self.pixelSize = pixelSize
        self.frameRate = frameRate
        self.hasAudio = hasAudio
        self.thumbnailURL = thumbnailURL
    }

    var isPortrait: Bool { pixelSize.height > pixelSize.width }

    var aspectRatio: CGFloat {
        guard pixelSize.height > 0 else { return 16.0 / 9.0 }
        return pixelSize.width / pixelSize.height
    }

    /// e.g. "1080 × 1920"
    var resolutionDescription: String {
        "\(Int(pixelSize.width.rounded())) × \(Int(pixelSize.height.rounded()))"
    }

    /// e.g. "4K", "1080p" - the shorthand people actually recognise.
    var qualityLabel: String? {
        let shortSide = min(pixelSize.width, pixelSize.height)
        switch shortSide {
        case 2000...: return "4K"
        case 1400..<2000: return "2K"
        case 1000..<1400: return "1080p"
        case 640..<1000: return "720p"
        default: return nil
        }
    }

    var frameRateDescription: String {
        String(format: "%g fps", (frameRate * 100).rounded() / 100)
    }
}

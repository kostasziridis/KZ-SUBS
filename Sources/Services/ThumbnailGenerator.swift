import AVFoundation
import UIKit

/// Makes still frames for project cards and the export screen.
enum ThumbnailGenerator {

    /// Renders a frame from `asset` and writes it to the thumbnails directory.
    /// - Returns: the thumbnail file URL, or `nil` when no frame could be produced.
    static func makeThumbnail(
        for videoURL: URL,
        duration: TimeInterval,
        maximumSize: CGSize = CGSize(width: 800, height: 800)
    ) async -> URL? {
        let asset = AVURLAsset(url: videoURL)
        let generator = AVAssetImageGenerator(asset: asset)
        // Honours the track transform, so portrait clips are not laid on their side.
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = maximumSize
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.5, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.5, preferredTimescale: 600)

        let seconds = duration > 0 ? min(1.0, duration / 3.0) : 0
        let time = CMTime(seconds: seconds, preferredTimescale: 600)

        do {
            let (cgImage, _) = try await generator.image(at: time)
            guard let data = UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.85) else { return nil }

            StorageManager.ensureDirectoryExists(StorageManager.thumbnailsDirectory)
            let url = StorageManager.uniqueURL(
                in: StorageManager.thumbnailsDirectory,
                preferredName: "\(UUID().uuidString).jpg",
                fallbackExtension: "jpg"
            )
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            AppLog.media.error("Thumbnail generation failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}

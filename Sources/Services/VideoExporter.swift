import AVFoundation
import SwiftUI
import UIKit

/// One drawn caption and the stretch of the timeline it is on screen for.
///
/// `@unchecked Sendable` with a reason: the only reference type here is a `CGImage`,
/// which is immutable once created and is never written to after rasterising.
struct CaptionFrame: @unchecked Sendable {
    let image: CGImage
    let size: CGSize
    let start: TimeInterval
    let end: TimeInterval
}

/// Draws captions into images, on the main actor because `ImageRenderer` requires it.
///
/// Renders `CaptionBlockView` - the very same view the editor previews - so the file
/// the user gets is the design they made, not a re-implementation of it.
@MainActor
enum CaptionRasterizer {

    /// Beyond this many separately drawn captions the layer tree costs more memory
    /// than is reasonable on a phone, so word-by-word highlighting is dropped and one
    /// image per subtitle is drawn instead. The caller is told when that happens.
    static let maximumFrames = 400

    struct Output {
        var frames: [CaptionFrame]
        /// True when highlighting had to be dropped to keep memory sane.
        var simplifiedHighlighting: Bool
    }

    static func rasterize(
        segments: [SubtitleSegment],
        style: CaptionStyle,
        renderSize: CGSize
    ) -> Output {
        let wantsWordFrames = style.highlightsSpokenWord
        let wordFrameCount = segments.reduce(0) { $0 + ($1.words?.count ?? 1) }
        let useWordFrames = wantsWordFrames && wordFrameCount <= maximumFrames

        var frames: [CaptionFrame] = []

        for segment in separate(segments) {
            if useWordFrames, let words = segment.words, !words.isEmpty {
                for (index, word) in words.enumerated() {
                    // Stretch the first and last word to the subtitle's own bounds so
                    // there is never a flicker of nothing between words.
                    let start = max(index == 0 ? segment.startTime : word.startTime, segment.startTime)
                    let end = min(index == words.count - 1 ? segment.endTime : words[index + 1].startTime, segment.endTime)
                    // A subtitle cut short where the next one begins takes the words it
                    // no longer has time to speak with it.
                    guard end > start else { continue }

                    if let frame = render(segment, style: style, at: word.startTime, renderSize: renderSize, start: start, end: end) {
                        frames.append(frame)
                    }
                }
            } else {
                // A time before every word, so nothing is highlighted.
                if let frame = render(segment, style: style, at: -1, renderSize: renderSize, start: segment.startTime, end: segment.endTime) {
                    frames.append(frame)
                }
            }
        }

        return Output(frames: frames, simplifiedHighlighting: wantsWordFrames && !useWordFrames)
    }

    /// Stops a subtitle from still being on screen when the next one arrives.
    ///
    /// Subtitles run one after another, and the editor relies on it - it looks up the
    /// single subtitle covering a moment and shows that one. Speech engines make no
    /// such promise: a decoding window can hand back a subtitle whose end runs seconds
    /// past its own words and straight through the three that follow. Burnt into the
    /// video that was two subtitles printed over each other, in a file the editor had
    /// shown as clean.
    ///
    /// Done here, over whole subtitles, rather than over the drawn word frames: cutting
    /// the frames alone lets a long subtitle reclaim the screen between the words of
    /// the one that replaced it, and the caption flicks back and forth between the two.
    ///
    /// Cut rather than dropped, because the words in a long subtitle were still spoken;
    /// it is only its welcome that outstays. One that is left no time at all has been
    /// wholly covered by its neighbour, and goes.
    static func separate(_ segments: [SubtitleSegment]) -> [SubtitleSegment] {
        let ordered = segments.sorted { $0.startTime < $1.startTime }
        var result: [SubtitleSegment] = []

        for (index, segment) in ordered.enumerated() {
            guard index + 1 < ordered.count else {
                result.append(segment)
                continue
            }

            // Only the next one needs consulting: everything after it starts later
            // still, so cutting each at its immediate successor leaves the run in order.
            let next = ordered[index + 1]
            // Two subtitles claiming the same instant - this one never gets to show.
            guard next.startTime > segment.startTime else { continue }

            var trimmed = segment
            trimmed.endTime = min(segment.endTime, next.startTime)
            result.append(trimmed)
        }

        return result
    }

    private static func render(
        _ segment: SubtitleSegment,
        style: CaptionStyle,
        at time: TimeInterval,
        renderSize: CGSize,
        start: TimeInterval,
        end: TimeInterval
    ) -> CaptionFrame? {
        guard end > start else { return nil }

        let view = CaptionBlockView(
            segment: segment,
            style: style,
            currentTime: time,
            frameHeight: renderSize.height
        )

        let renderer = ImageRenderer(content: view)
        // Already working in video pixels, so no extra scale factor.
        renderer.scale = 1
        renderer.isOpaque = false
        renderer.proposedSize = ProposedViewSize(
            width: renderSize.width * CaptionLayout.maximumWidthFraction,
            height: nil
        )

        guard let image = renderer.cgImage else { return nil }

        return CaptionFrame(
            image: image,
            size: CGSize(width: image.width, height: image.height),
            start: start,
            end: end
        )
    }
}

/// Burns subtitles permanently into a copy of the video.
actor VideoExporter {

    static let shared = VideoExporter()

    struct Result: Sendable {
        let url: URL
        /// True when the export drew one caption per subtitle rather than per word.
        let simplifiedHighlighting: Bool
    }

    private init() {}

    /// - Parameter onProgress: 0...1.
    /// - Throws: `CancellationError` when the surrounding task is cancelled.
    func export(
        project: SubtitleProject,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws -> Result {

        let asset = AVURLAsset(url: project.videoURL, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])

        guard let sourceVideo = try await asset.loadTracks(withMediaType: .video).first else {
            throw AppError.exportFailed
        }

        let duration = try await asset.load(.duration)
        let (naturalSize, transform, nominalFrameRate) = try await sourceVideo.load(
            .naturalSize, .preferredTransform, .nominalFrameRate
        )

        // The size the viewer actually sees: the stored size with the track's rotation
        // applied, so portrait video exports portrait instead of on its side.
        let rotated = naturalSize.applying(transform)
        let renderSize = CGSize(width: abs(rotated.width).rounded(), height: abs(rotated.height).rounded())

        guard StorageManager.hasRoom(for: estimatedSize(duration: duration.seconds, size: renderSize)) else {
            throw AppError.notEnoughStorage
        }

        // MARK: Composition

        let composition = AVMutableComposition()
        guard let videoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else { throw AppError.exportFailed }

        let range = CMTimeRange(start: .zero, duration: duration)
        try videoTrack.insertTimeRange(range, of: sourceVideo, at: .zero)

        if let sourceAudio = try await asset.loadTracks(withMediaType: .audio).first,
           let audioTrack = composition.addMutableTrack(
               withMediaType: .audio,
               preferredTrackID: kCMPersistentTrackID_Invalid
           ) {
            try audioTrack.insertTimeRange(range, of: sourceAudio, at: .zero)
        }

        try Task.checkCancellation()

        // MARK: Captions

        let rasterized = await CaptionRasterizer.rasterize(
            segments: project.subtitles,
            style: project.captionStyle,
            renderSize: renderSize
        )

        try Task.checkCancellation()

        // MARK: Video composition

        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = renderSize
        let fps = nominalFrameRate > 0 ? Double(nominalFrameRate) : 30
        videoComposition.frameDuration = CMTime(value: 1, timescale: CMTimeScale(max(24, fps.rounded())))
        videoComposition.customVideoCompositorClass = CaptionVideoCompositor.self

        let captions = place(
            rasterized.frames,
            style: project.captionStyle,
            renderSize: renderSize
        )

        videoComposition.instructions = [
            CaptionCompositionInstruction(
                timeRange: range,
                trackID: videoTrack.trackID,
                captions: captions,
                transform: transform,
                renderSize: renderSize
            )
        ]

        // MARK: Export

        StorageManager.ensureDirectoryExists(StorageManager.workingDirectory)
        let outputURL = StorageManager.uniqueURL(
            in: StorageManager.workingDirectory,
            preferredName: "\(project.name)-subtitled.mp4",
            fallbackExtension: "mp4"
        )
        try? FileManager.default.removeItem(at: outputURL)

        guard let session = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetHighestQuality
        ) else { throw AppError.exportFailed }

        session.videoComposition = videoComposition

        let progressTask = Task {
            for await state in session.states(updateInterval: 0.25) {
                if case let .exporting(progress) = state {
                    onProgress(progress.fractionCompleted)
                }
            }
        }
        defer { progressTask.cancel() }

        do {
            try await session.export(to: outputURL, as: .mp4)
        } catch {
            try? FileManager.default.removeItem(at: outputURL)
            if Task.isCancelled { throw CancellationError() }
            AppLog.media.error("Export failed: \(error.localizedDescription, privacy: .public)")
            throw AppError.exportFailed
        }

        onProgress(1)
        AppLog.media.info("Exported \(outputURL.lastPathComponent, privacy: .public)")

        return Result(url: outputURL, simplifiedHighlighting: rasterized.simplifiedHighlighting)
    }

    // MARK: - Placement

    /// Moves each rendered caption to where the editor put it.
    ///
    /// Core Image measures from the bottom-left while the editor works top-left, so
    /// the vertical position is mirrored once here.
    private func place(
        _ frames: [CaptionFrame],
        style: CaptionStyle,
        renderSize: CGSize
    ) -> [PositionedCaption] {

        frames.map { frame in
            // The same rule the preview applies, so a caption that fits on screen fits
            // in the file and one that had to shrink shrinks by the same amount.
            let scale = CaptionLayout.fitScale(captionSize: frame.size, frameSize: renderSize)
            let drawn = CGSize(width: frame.size.width * scale, height: frame.size.height * scale)

            let center = CaptionLayout.center(
                style: style,
                captionSize: drawn,
                frameSize: renderSize
            )

            let originX = center.x - drawn.width / 2
            let originYFromTop = center.y - drawn.height / 2
            let originYFromBottom = renderSize.height - originYFromTop - drawn.height

            var image = CIImage(cgImage: frame.image)
            if scale < 1 {
                image = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            }
            image = image.transformed(by: CGAffineTransform(translationX: originX, y: originYFromBottom))

            return PositionedCaption(image: image, start: frame.start, end: frame.end)
        }
    }

    private func estimatedSize(duration: Double, size: CGSize) -> Int64 {
        // A generous guess: high quality 1080p runs about 2 MB per second.
        let perSecond = max(1.0, (size.width * size.height) / (1920 * 1080)) * 2_000_000
        return Int64(max(0, duration) * perSecond) + 50_000_000
    }
}

#if DEBUG
import Foundation
import CoreGraphics

/// Sample data so SwiftUI previews never need real media - or, later, WhisperKit.
extension VideoAsset {
    static let sample = VideoAsset(
        url: URL(fileURLWithPath: "/dev/null/Sample Clip.mov"),
        filename: "Sample Clip.mov",
        duration: 321,
        pixelSize: CGSize(width: 1080, height: 1920),
        frameRate: 30,
        hasAudio: true
    )

    static let sampleLandscape = VideoAsset(
        url: URL(fileURLWithPath: "/dev/null/Interview.mp4"),
        filename: "Interview.mp4",
        duration: 92,
        pixelSize: CGSize(width: 3840, height: 2160),
        frameRate: 60,
        hasAudio: true
    )
}

extension SubtitleSegment {
    static let samples: [SubtitleSegment] = [
        SubtitleSegment(startTime: 1.24, endTime: 3.85, text: "Καλημέρα σε όλους."),
        SubtitleSegment(startTime: 3.85, endTime: 6.20, text: "Σήμερα θα δούμε\nκάτι καινούργιο."),
        SubtitleSegment(startTime: 6.40, endTime: 9.10, text: "Let's take a look together.")
    ]
}

extension SubtitleProject {
    static let sample = SubtitleProject(
        createdAt: Date(timeIntervalSinceNow: -86_400),
        updatedAt: Date(timeIntervalSinceNow: -7_200),
        name: "Sample Clip",
        videoURL: URL(fileURLWithPath: "/dev/null/Sample Clip.mov"),
        thumbnailURL: nil,
        duration: 321,
        pixelSize: CGSize(width: 1080, height: 1920),
        language: .greek,
        subtitles: SubtitleSegment.samples
    )

    static let sampleEnglish = SubtitleProject(
        createdAt: Date(timeIntervalSinceNow: -400_000),
        updatedAt: Date(timeIntervalSinceNow: -260_000),
        name: "Interview",
        videoURL: URL(fileURLWithPath: "/dev/null/Interview.mp4"),
        thumbnailURL: nil,
        duration: 92,
        pixelSize: CGSize(width: 3840, height: 2160),
        language: .english,
        subtitles: []
    )
}

extension AppState {
    static var previewEmpty: AppState {
        let state = AppState()
        state.applyPreviewProjects([])
        return state
    }

    static var previewPopulated: AppState {
        let state = AppState()
        state.applyPreviewProjects([.sample, .sampleEnglish])
        return state
    }
}
#endif

import Foundation
import Observation

/// Drives the imported-video screen: the details shown, and the choices made
/// before subtitles are generated.
@MainActor
@Observable
final class VideoImportViewModel {

    let asset: VideoAsset
    var language: AppLanguage
    var captionStyle: CaptionStyle

    init(asset: VideoAsset, language: AppLanguage = .automatic, captionStyle: CaptionStyle = .default) {
        self.asset = asset
        self.language = language
        self.captionStyle = captionStyle
    }

    var title: String { FileHelpers.displayName(for: asset.url) }

    var durationText: String { TimecodeFormatter.duration(asset.duration) }

    var resolutionText: String {
        if let quality = asset.qualityLabel {
            return "\(asset.resolutionDescription) · \(quality)"
        }
        return asset.resolutionDescription
    }

    var fileSizeText: String? {
        StorageManager.fileSize(of: asset.url).map(FileHelpers.formattedSize)
    }

    /// Subtitles need speech; without an audio track there is nothing to transcribe.
    var canGenerateSubtitles: Bool { asset.hasAudio }

    /// The project this screen would produce. Used from the next phase onward.
    func makeProject() -> SubtitleProject {
        SubtitleProject(asset: asset, language: language)
    }
}

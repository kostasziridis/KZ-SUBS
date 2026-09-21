import Foundation

/// Every failure the user can be shown, in plain language.
/// Technical detail belongs in the log, never on screen.
enum AppError: LocalizedError, Identifiable, Equatable {
    case unableToLoadVideo
    case videoHasNoAudio
    case unableToPrepareModel
    case unableToGenerateSubtitles
    case notEnoughStorage
    case exportFailed
    case photosAccessUnavailable

    var id: String { String(describing: self) }

    var errorDescription: String? {
        switch self {
        case .unableToLoadVideo: return String(localized: "Unable to load video")
        case .videoHasNoAudio: return String(localized: "This video has no sound")
        case .unableToPrepareModel: return String(localized: "Unable to prepare subtitles")
        case .unableToGenerateSubtitles: return String(localized: "Unable to generate subtitles")
        case .notEnoughStorage: return String(localized: "Not enough storage")
        case .exportFailed: return String(localized: "Export failed")
        case .photosAccessUnavailable: return String(localized: "Photos access unavailable")
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .unableToLoadVideo:
            return String(localized: "This video could not be opened. Try choosing it again, or pick a different one.")
        case .videoHasNoAudio:
            return String(localized: "Subtitles need speech to work with. Choose a video that contains sound.")
        case .unableToPrepareModel:
            return String(localized: "The one-time setup could not finish. Check your connection and try again — after this, subtitles work offline.")
        case .unableToGenerateSubtitles:
            return String(localized: "Something interrupted the process. Try generating subtitles again.")
        case .notEnoughStorage:
            return String(localized: "Free up some space on your iPhone and try again.")
        case .exportFailed:
            return String(localized: "The video could not be finished. Try exporting again.")
        case .photosAccessUnavailable:
            return String(localized: "Allow KZ-SUBS to add videos to your photo library in Settings to save your export.")
        }
    }

    var symbolName: String {
        switch self {
        case .unableToLoadVideo: return "film.slash"
        case .videoHasNoAudio: return "speaker.slash.fill"
        case .unableToPrepareModel, .unableToGenerateSubtitles: return "exclamationmark.bubble.fill"
        case .notEnoughStorage: return "internaldrive.fill"
        case .exportFailed: return "square.and.arrow.up.trianglebadge.exclamationmark"
        case .photosAccessUnavailable: return "photo.badge.exclamationmark"
        }
    }
}

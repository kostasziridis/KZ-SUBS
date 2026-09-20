import Foundation

/// What the speech engine produced, in the app's own vocabulary.
///
/// Nothing above this type knows WhisperKit exists.
struct SpeechTranscript: Sendable, Equatable {
    var text: String
    /// ISO-639-1 code the engine settled on, useful when the user chose Auto Detect.
    var detectedLanguageCode: String
    var segments: [SubtitleSegment]
    /// Wall-clock seconds the transcription took, for development logging.
    var processingTime: TimeInterval

    var detectedLanguageDisplayName: String {
        switch detectedLanguageCode {
        case "el": return "Ελληνικά"
        case "en": return "English"
        default:
            return Locale.current.localizedString(forLanguageCode: detectedLanguageCode)
                ?? detectedLanguageCode.uppercased()
        }
    }
}

/// Stages of getting the speech model ready, so the UI can say something honest
/// instead of pretending a download is transcription progress.
enum ModelPreparation: Sendable, Equatable {
    case checking
    case downloading(Double)
    case loading
    case ready
}

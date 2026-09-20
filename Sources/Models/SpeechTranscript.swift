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
    var timings: SpeechTimings?

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

/// Where the time went. Kept so a slow run can be diagnosed with numbers rather
/// than guesses - above all, whether the cost was one-time model specialisation or
/// the transcription itself.
struct SpeechTimings: Sendable, Equatable {
    /// Our own measurement of preparing the model, download excluded.
    var modelPreparation: TimeInterval
    /// Core ML compiling the model for this specific chip. Paid once, then cached by
    /// the system - but the cache is dropped after OS updates and long idle periods.
    var specialization: TimeInterval
    var audioSeconds: TimeInterval
    var encoding: TimeInterval
    var decodingLoop: TimeInterval
    var transcription: TimeInterval

    /// Seconds of audio handled per second of work. Above 1 is faster than realtime.
    var realtimeFactor: Double {
        transcription > 0 ? audioSeconds / transcription : 0
    }

    var summary: String {
        String(
            format: "prepare %.1fs (specialise %.1fs) · transcribe %.1fs for %.0fs audio (%.1fx realtime) · encode %.1fs decode %.1fs",
            modelPreparation, specialization, transcription, audioSeconds, realtimeFactor, encoding, decodingLoop
        )
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

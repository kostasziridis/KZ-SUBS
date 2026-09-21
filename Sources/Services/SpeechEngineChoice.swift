import Foundation

/// Which engine listens to the video.
///
/// Two, on purpose. They are trained differently and fail differently, and which one
/// is better on a particular voice, accent and room is not something a benchmark can
/// answer for someone else's video. Both run entirely on the phone.
enum SpeechEngineChoice: String, CaseIterable, Identifiable, Sendable {
    case whisper
    case parakeet

    var id: String { rawValue }

    /// Named for what they are to the user, not for whose model they are.
    var displayName: String {
        switch self {
        case .whisper: return String(localized: "Standard engine")
        case .parakeet: return String(localized: "Alternative engine")
        }
    }

    var detail: String {
        switch self {
        case .whisper:
            return String(localized: "The one the app has always used. Accurate, and the only one that can use your vocabulary.")
        case .parakeet:
            return String(localized: "A smaller, faster model. Worth trying if the standard one mishears you.")
        }
    }

    var approximateSize: String {
        switch self {
        case .whisper: return "~630 MB"
        case .parakeet: return "~600 MB"
        }
    }

    /// True where the vocabulary is honoured, so the UI never promises what an engine
    /// cannot do.
    var supportsVocabulary: Bool {
        switch self {
        case .whisper: return true
        case .parakeet: return false
        }
    }

    // MARK: - Persistence

    private static let key = "speechEngine"

    static var current: SpeechEngineChoice {
        get {
            guard let raw = UserDefaults.standard.string(forKey: key) else { return .whisper }
            return SpeechEngineChoice(rawValue: raw) ?? .whisper
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: key) }
    }
}

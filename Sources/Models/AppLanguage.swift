import Foundation

/// The spoken language the user expects in the video.
///
/// `automatic` lets the speech engine decide; the other cases pin recognition to a
/// specific language, which is measurably more accurate when the user already knows it.
enum AppLanguage: String, Codable, CaseIterable, Identifiable, Hashable {
    case automatic
    case greek
    case english

    var id: String { rawValue }

    /// Name shown in the UI, written in the language it represents.
    var displayName: String {
        switch self {
        case .automatic: return String(localized: "Auto Detect")
        case .greek: return "Ελληνικά"
        case .english: return "English"
        }
    }

    /// ISO-639-1 code passed to the speech engine. `nil` means "detect".
    var languageCode: String? {
        switch self {
        case .automatic: return nil
        case .greek: return "el"
        case .english: return "en"
        }
    }

    /// Maps a code the speech engine reported back onto a case we know.
    init?(languageCode: String) {
        switch languageCode.lowercased() {
        case "el": self = .greek
        case "en": self = .english
        default: return nil
        }
    }

    var symbolName: String {
        switch self {
        case .automatic: return "wand.and.stars"
        case .greek, .english: return "character.bubble"
        }
    }
}

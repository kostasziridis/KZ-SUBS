import Foundation

/// How subtitles are drawn over the video.
///
/// Deliberately independent of the transcription data: the same segments can be
/// restyled endlessly without touching timings or text.
struct CaptionStyle: Codable, Equatable, Hashable {
    enum Preset: String, Codable, CaseIterable, Identifiable {
        /// White bold text with a black shadow.
        case shadow
        /// White bold text on a black rounded background.
        case block
        /// Larger, heavier social-video caption.
        case social

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .shadow: return "Shadow"
            case .block: return "Block"
            case .social: return "Social"
            }
        }
    }

    enum TextAlignment: String, Codable, CaseIterable, Identifiable {
        case leading, center, trailing

        var id: String { rawValue }

        var symbolName: String {
            switch self {
            case .leading: return "text.alignleft"
            case .center: return "text.aligncenter"
            case .trailing: return "text.alignright"
            }
        }
    }

    var preset: Preset
    /// Font size expressed against a 1080-point-tall reference frame, so the same
    /// style looks identical on a preview and in a 4K export.
    var referenceFontSize: Double
    /// 0 = top of the safe area, 1 = bottom of the safe area.
    var verticalPosition: Double
    var alignment: TextAlignment
    /// Karaoke-style highlighting. Off by default until word timings prove reliable.
    var highlightsSpokenWord: Bool

    static let `default` = CaptionStyle(
        preset: .shadow,
        referenceFontSize: 56,
        verticalPosition: 0.86,
        alignment: .center,
        highlightsSpokenWord: false
    )

    /// Scales `referenceFontSize` to whatever frame the captions are drawn in.
    func fontSize(forFrameHeight height: Double) -> Double {
        guard height > 0 else { return referenceFontSize }
        return referenceFontSize * (height / 1080.0)
    }
}

import SwiftUI

/// Shows a caption style on a neutral backdrop, so changes are visible immediately.
struct CaptionStylePreview: View {
    let style: CaptionStyle
    let segment: SubtitleSegment?
    /// Sweeps so karaoke highlighting can be seen standing still.
    var animatedTime: TimeInterval = 0

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.16, green: 0.17, blue: 0.24), Color(red: 0.07, green: 0.08, blue: 0.12)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            CaptionOverlayView(
                segment: segment ?? Self.placeholder,
                style: style,
                currentTime: animatedTime
            )
        }
        .frame(height: 170)
        .clipShape(AppTheme.cardShape(AppTheme.controlRadius))
        .overlay {
            AppTheme.cardShape(AppTheme.controlRadius)
                .strokeBorder(AppTheme.hairline, lineWidth: 1)
        }
    }

    /// Used when a project has no subtitles yet to preview with.
    static let placeholder = SubtitleSegment(
        startTime: 0,
        endTime: 3,
        text: "Σήμερα θα δούμε\nκάτι καινούργιο",
        words: [
            SubtitleWord(word: "Σήμερα", startTime: 0, endTime: 0.75),
            SubtitleWord(word: "θα", startTime: 0.75, endTime: 1.1),
            SubtitleWord(word: "δούμε", startTime: 1.1, endTime: 1.8),
            SubtitleWord(word: "κάτι", startTime: 1.8, endTime: 2.3),
            SubtitleWord(word: "καινούργιο", startTime: 2.3, endTime: 3.0)
        ]
    )
}

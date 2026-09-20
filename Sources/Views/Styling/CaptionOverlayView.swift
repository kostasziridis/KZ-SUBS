import SwiftUI

/// Draws one subtitle over the video, in whatever style the project uses.
///
/// Sizes itself from the frame it is given, so the same style looks right in a small
/// preview and in a full-resolution export.
struct CaptionOverlayView: View {

    let segment: SubtitleSegment?
    let style: CaptionStyle
    /// Playback position, used only for word-by-word highlighting.
    var currentTime: TimeInterval = 0

    var body: some View {
        GeometryReader { proxy in
            if let segment, !segment.text.isEmpty {
                caption(for: segment, in: proxy.size)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    // verticalPosition is measured from the top, so the gap below it
                    // is what is left over.
                    .padding(.bottom, max(0, proxy.size.height * (1 - style.verticalPosition)))
                    .padding(.horizontal, proxy.size.width * 0.05)
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: - Caption

    private func caption(for segment: SubtitleSegment, in size: CGSize) -> some View {
        let fontSize = style.fontSize(forFrameHeight: size.height)

        return text(for: segment)
            .font(.system(size: fontSize, weight: style.weight.fontWeight, design: style.fontDesign.design))
            .multilineTextAlignment(style.alignment.swiftUI)
            .lineSpacing(fontSize * 0.12)
            .padding(.horizontal, style.background == .none ? 0 : fontSize * 0.45)
            .padding(.vertical, style.background == .none ? 0 : fontSize * 0.22)
            .background { backgroundShape }
            .shadow(
                color: style.background == .shadow ? style.backgroundColor.color : .clear,
                radius: fontSize * 0.06,
                x: 0,
                y: fontSize * 0.035
            )
            .frame(maxWidth: .infinity, alignment: style.alignment.frameAlignment)
    }

    @ViewBuilder
    private var backgroundShape: some View {
        switch style.background {
        case .block:
            Rectangle().fill(style.backgroundColor.color)
        case .roundedBlock:
            RoundedRectangle(cornerRadius: 12, style: .continuous).fill(style.backgroundColor.color)
        case .shadow, .none:
            Color.clear
        }
    }

    // MARK: - Text

    /// Builds the line as a single `Text`.
    ///
    /// Per-word styling goes through `AttributedString` rather than concatenated `Text`
    /// runs, because only attributed runs can carry a background - and a box behind the
    /// spoken word is the whole point of the Spotlight style. Wrapping still works,
    /// which hand-laying words out in an HStack would break.
    private func text(for segment: SubtitleSegment) -> Text {
        let words = segment.words ?? []
        let needsPerWord = !words.isEmpty
            && (style.highlightsSpokenWord || words.contains { $0.colorOverride != nil })

        guard needsPerWord else {
            return Text(display(segment.text))
                .foregroundStyle(style.textColor.color)
        }
        return Text(attributed(words))
    }

    private func attributed(_ words: [SubtitleWord]) -> AttributedString {
        var result = AttributedString()

        for (index, word) in words.enumerated() {
            var run = AttributedString(display(word.word))
            let isSpoken = currentTime >= word.startTime && currentTime < word.endTime

            // A colour chosen by hand for this word beats anything the style would do.
            if let override = word.colorOverride {
                run.foregroundColor = override.color
            } else if isSpoken, style.spokenWordEffect == .colour {
                run.foregroundColor = style.highlightColor.color
            } else {
                run.foregroundColor = style.textColor.color
            }

            if isSpoken, style.spokenWordEffect == .box {
                run.backgroundColor = style.spokenWordBackgroundColor.color
            }

            if index > 0 { result += AttributedString(" ") }
            result += run
        }

        return result
    }

    private func display(_ value: String) -> String {
        style.isUppercased ? value.captionUppercased() : value
    }
}

#Preview("Styles") {
    VStack(spacing: 12) {
        ForEach(CaptionStyle.Preset.allCases) { preset in
            ZStack {
                LinearGradient(
                    colors: [.purple.opacity(0.7), .blue.opacity(0.7)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
                CaptionOverlayView(
                    segment: SubtitleSegment.samples[1],
                    style: .preset(preset),
                    currentTime: 4.6
                )
            }
            .frame(height: 150)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(alignment: .topLeading) {
                Text(preset.displayName)
                    .font(.caption2.weight(.semibold))
                    .padding(6)
                    .foregroundStyle(.white)
            }
        }
    }
    .padding()
    .appBackground()
    .preferredColorScheme(.dark)
}

import SwiftUI

/// The caption itself - text, colours, word boxes - with no opinion about where it
/// sits in the frame.
///
/// Shared by the live preview and the video export. They must not be two separate
/// implementations, or the exported file slowly stops matching what the user designed.
struct CaptionBlockView: View {

    let segment: SubtitleSegment
    let style: CaptionStyle
    var currentTime: TimeInterval = 0
    /// Height of the frame the caption is being drawn into, which is what the font
    /// size is measured against.
    let frameHeight: CGFloat

    private var fontSize: CGFloat { style.fontSize(forFrameHeight: frameHeight) }

    var body: some View {
        content
            .font(.system(size: fontSize, weight: style.weight.fontWeight, design: style.fontDesign.design))
            .padding(.horizontal, style.background == .none ? 0 : fontSize * 0.45)
            .padding(.vertical, style.background == .none ? 0 : fontSize * 0.22)
            .background { backgroundShape }
            .shadow(
                color: style.background == .shadow ? style.backgroundColor.color : .clear,
                radius: fontSize * 0.06,
                x: 0,
                y: fontSize * 0.035
            )
    }

    @ViewBuilder
    private var content: some View {
        if needsPerWordRendering, let words = segment.words {
            CaptionFlowLayout(
                alignment: style.alignment,
                spacing: fontSize * 0.04,
                lineSpacing: fontSize * 0.1
            ) {
                ForEach(words) { word in
                    wordView(word)
                }
            }
        } else {
            Text(display(segment.text))
                .foregroundStyle(style.textColor.color)
                .multilineTextAlignment(style.alignment.swiftUI)
                .lineSpacing(fontSize * 0.12)
        }
    }

    /// Words only need laying out one by one when something distinguishes them.
    private var needsPerWordRendering: Bool {
        guard let words = segment.words, !words.isEmpty else { return false }
        return style.highlightsSpokenWord || words.contains { $0.colorOverride != nil }
    }

    private func wordView(_ word: SubtitleWord) -> some View {
        let isSpoken = currentTime >= word.startTime && currentTime < word.endTime
        let showsBox = isSpoken && style.spokenWordEffect == .box

        // A colour chosen by hand for this word beats anything the style would do.
        let colour: Color = {
            if let override = word.colorOverride { return override.color }
            if isSpoken, style.spokenWordEffect == .colour { return style.highlightColor.color }
            return style.textColor.color
        }()

        return Text(display(word.word))
            .foregroundStyle(colour)
            // Padding is constant whether or not the box is showing. If it were not,
            // every word would shift sideways as the highlight passed over it.
            .padding(.horizontal, fontSize * 0.16)
            .padding(.vertical, fontSize * 0.05)
            .background {
                if showsBox {
                    RoundedRectangle(cornerRadius: fontSize * 0.22, style: .continuous)
                        .fill(style.spokenWordBackgroundColor.color)
                }
            }
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

    private func display(_ value: String) -> String {
        style.isUppercased ? value.captionUppercased() : value
    }
}

/// Where the caption sits. Shared for the same reason the appearance is.
enum CaptionLayout {

    /// The widest a caption may be, as a share of the frame.
    static let maximumWidthFraction: CGFloat = 0.9

    /// The centre point for a caption of `captionSize` inside `frameSize`, pulled back
    /// at the edges so it always stays wholly on screen.
    static func center(
        style: CaptionStyle,
        captionSize: CGSize,
        frameSize: CGSize
    ) -> CGPoint {
        let halfWidth = min(captionSize.width / 2, frameSize.width / 2)
        let halfHeight = min(captionSize.height / 2, frameSize.height / 2)

        return CGPoint(
            x: min(max(style.horizontalPosition * frameSize.width, halfWidth), frameSize.width - halfWidth),
            y: min(max(style.verticalPosition * frameSize.height, halfHeight), frameSize.height - halfHeight)
        )
    }
}

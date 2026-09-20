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

        return Group {
            if needsPerWordRendering(segment), let words = segment.words {
                CaptionFlowLayout(
                    alignment: style.alignment,
                    spacing: fontSize * 0.04,
                    lineSpacing: fontSize * 0.1
                ) {
                    ForEach(words) { word in
                        wordView(word, fontSize: fontSize)
                    }
                }
            } else {
                Text(display(segment.text))
                    .foregroundStyle(style.textColor.color)
                    .multilineTextAlignment(style.alignment.swiftUI)
                    .lineSpacing(fontSize * 0.12)
            }
        }
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
        .frame(maxWidth: .infinity, alignment: style.alignment.frameAlignment)
    }

    /// Words only need laying out one by one when something distinguishes them.
    private func needsPerWordRendering(_ segment: SubtitleSegment) -> Bool {
        guard let words = segment.words, !words.isEmpty else { return false }
        return style.highlightsSpokenWord || words.contains { $0.colorOverride != nil }
    }

    private func wordView(_ word: SubtitleWord, fontSize: CGFloat) -> some View {
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

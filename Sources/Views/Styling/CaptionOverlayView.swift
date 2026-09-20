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
    /// Supply this and the caption can be dragged and pinched straight on the video,
    /// writing the new position and size back. Left nil, the caption is inert - which
    /// is what playback, the style preview and the export all want.
    var editing: Binding<CaptionStyle>?

    @State private var captionSize: CGSize = .zero
    @State private var positionAtDragStart: CGPoint?
    @State private var fontSizeAtPinchStart: Double?
    @State private var isAdjusting = false

    var body: some View {
        GeometryReader { proxy in
            if let segment, !segment.text.isEmpty {
                interactive(
                    caption(for: segment, in: proxy.size)
                        .frame(maxWidth: proxy.size.width * 0.9)
                        .background { sizeReader }
                        .overlay { adjustingOutline },
                    in: proxy.size
                )
            }
        }
        // Inert unless it is being edited, so a tap on the video still reaches the
        // player underneath.
        .allowsHitTesting(editing != nil)
    }

    // MARK: - Placement

    @ViewBuilder
    private func interactive(_ content: some View, in size: CGSize) -> some View {
        if let editing {
            content
                .position(position(in: size))
                .gesture(dragGesture(in: size, style: editing))
                .simultaneousGesture(pinchGesture(style: editing))
        } else {
            content.position(position(in: size))
        }
    }

    /// Keeps the caption fully on screen whatever position is stored, by pulling it
    /// back by its own half-width and half-height at the edges.
    private func position(in size: CGSize) -> CGPoint {
        let halfWidth = min(captionSize.width / 2, size.width / 2)
        let halfHeight = min(captionSize.height / 2, size.height / 2)

        return CGPoint(
            x: min(max(style.horizontalPosition * size.width, halfWidth), size.width - halfWidth),
            y: min(max(style.verticalPosition * size.height, halfHeight), size.height - halfHeight)
        )
    }

    private var sizeReader: some View {
        GeometryReader { proxy in
            Color.clear.preference(key: CaptionSizeKey.self, value: proxy.size)
        }
        .onPreferenceChange(CaptionSizeKey.self) { captionSize = $0 }
    }

    @ViewBuilder
    private var adjustingOutline: some View {
        if isAdjusting {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(AppTheme.accent, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                .padding(-6)
        }
    }

    // MARK: - Gestures

    private func dragGesture(in size: CGSize, style binding: Binding<CaptionStyle>) -> some Gesture {
        DragGesture()
            .onChanged { value in
                if positionAtDragStart == nil {
                    positionAtDragStart = CGPoint(
                        x: binding.wrappedValue.horizontalPosition,
                        y: binding.wrappedValue.verticalPosition
                    )
                    isAdjusting = true
                }
                guard let start = positionAtDragStart, size.width > 0, size.height > 0 else { return }

                binding.wrappedValue.horizontalPosition = clamped(start.x + value.translation.width / size.width)
                binding.wrappedValue.verticalPosition = clamped(start.y + value.translation.height / size.height)
            }
            .onEnded { _ in
                positionAtDragStart = nil
                isAdjusting = false
            }
    }

    private func pinchGesture(style binding: Binding<CaptionStyle>) -> some Gesture {
        MagnifyGesture()
            .onChanged { value in
                if fontSizeAtPinchStart == nil {
                    fontSizeAtPinchStart = binding.wrappedValue.referenceFontSize
                    isAdjusting = true
                }
                guard let base = fontSizeAtPinchStart else { return }
                // Same bounds as the size slider, so the two cannot disagree.
                binding.wrappedValue.referenceFontSize = min(140, max(24, base * value.magnification))
            }
            .onEnded { _ in
                fontSizeAtPinchStart = nil
                isAdjusting = false
            }
    }

    private func clamped(_ value: Double) -> Double {
        min(max(value, 0), 1)
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

/// Reports the caption's laid-out size, so it can be kept inside the frame.
private struct CaptionSizeKey: PreferenceKey {
    static let defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}

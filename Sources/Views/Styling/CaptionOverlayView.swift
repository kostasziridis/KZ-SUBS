import SwiftUI

/// Places a caption over the video.
///
/// The caption's appearance lives in `CaptionBlockView` and its placement in
/// `CaptionLayout`, both shared with the exporter - this view only adds the frame it
/// sits in and, when editing, the gestures that move and resize it.
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
                    CaptionBlockView(
                        segment: segment,
                        style: style,
                        currentTime: currentTime,
                        frameHeight: proxy.size.height
                    )
                    .frame(maxWidth: proxy.size.width * CaptionLayout.maximumWidthFraction)
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
                .position(CaptionLayout.center(style: style, captionSize: captionSize, frameSize: size))
                .gesture(dragGesture(in: size, style: editing))
                .simultaneousGesture(pinchGesture(style: editing))
        } else {
            content
                .position(CaptionLayout.center(style: style, captionSize: captionSize, frameSize: size))
        }
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
}

/// Reports the caption's laid-out size, so it can be kept inside the frame.
private struct CaptionSizeKey: PreferenceKey {
    static let defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
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
                    segment: CaptionStylePreview.placeholder,
                    style: .preset(preset),
                    currentTime: 1.4
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

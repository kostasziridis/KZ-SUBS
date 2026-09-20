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
    /// Supply this and tapping the caption edits its words in place, on the video.
    var text: Binding<String>?
    /// Called when in-place typing starts, so playback can be stopped.
    var onBeginTextEditing: (() -> Void)?
    /// The video's shape. Without it the caption is laid out in the whole view, which
    /// for a pillarboxed clip is wider than the picture - so the preview wraps the text
    /// differently from the export and the two stop matching. Nil means the view is
    /// the picture, which is what the style previews want.
    var contentAspectRatio: CGFloat?

    @State private var captionSize: CGSize = .zero
    @State private var positionAtDragStart: CGPoint?
    @State private var fontSizeAtPinchStart: Double?
    @State private var isAdjusting = false
    @State private var isEditingText = false

    var body: some View {
        GeometryReader { proxy in
            let content = contentRect(in: proxy.size)

            if let segment, !segment.text.isEmpty {
                interactive(
                    CaptionBlockView(
                        segment: segment,
                        style: style,
                        currentTime: currentTime,
                        frameHeight: content.height,
                        editingText: isEditingText ? text : nil,
                        onEndEditing: { isEditingText = false }
                    )
                    .frame(maxWidth: content.width * CaptionLayout.maximumWidthFraction)
                    .background { sizeReader }
                    .overlay { adjustingOutline }
                    .overlay { smallCaptionHint }
                    .overlay { editingOutline }
                    // A small caption is a small target. The padding is symmetric, so
                    // it grows what can be grabbed without moving what is drawn.
                    .padding(editing != nil ? 22 : 0)
                    .contentShape(Rectangle()),
                    in: content
                )
            }
        }
        // Inert unless it is being edited, so a tap on the video still reaches the
        // player underneath.
        .allowsHitTesting(editing != nil)
    }

    // MARK: - Placement

    /// Where the picture actually sits inside the view, once letterboxing or
    /// pillarboxing is taken into account.
    private func contentRect(in size: CGSize) -> CGRect {
        guard let aspect = contentAspectRatio, aspect > 0, size.width > 0, size.height > 0 else {
            return CGRect(origin: .zero, size: size)
        }

        if size.width / size.height > aspect {
            // Bars at the sides: the picture is limited by height.
            let width = size.height * aspect
            return CGRect(x: (size.width - width) / 2, y: 0, width: width, height: size.height)
        } else {
            // Bars above and below: limited by width.
            let height = size.width / aspect
            return CGRect(x: 0, y: (size.height - height) / 2, width: size.width, height: height)
        }
    }

    private func placement(in rect: CGRect) -> CGPoint {
        let center = CaptionLayout.center(style: style, captionSize: captionSize, frameSize: rect.size)
        return CGPoint(x: rect.minX + center.x, y: rect.minY + center.y)
    }

    @ViewBuilder
    private func interactive(_ content: some View, in rect: CGRect) -> some View {
        if let editing, !isEditingText {
            content
                .position(placement(in: rect))
                // One combined gesture, not two competing ones: a separate
                // `onTapGesture` claims the touch before the drag can start, which
                // leaves the caption unmovable. Exclusively means the drag is tried
                // first and the tap only runs when the finger did not travel.
                .gesture(
                    dragGesture(in: rect.size, style: editing)
                        .exclusively(before: TapGesture().onEnded { beginTextEditing() })
                )
                .simultaneousGesture(pinchGesture(style: editing))
        } else {
            // While the words are being typed, moving and resizing would only get in
            // the way - and would fight the keyboard for the same drags.
            content
                .position(placement(in: rect))
        }
    }

    private func beginTextEditing() {
        guard text != nil else { return }
        onBeginTextEditing?()
        withAnimation(.snappy(duration: 0.18)) { isEditingText = true }
    }

    /// A quiet frame while typing, so it is clear which caption is being changed.
    @ViewBuilder
    private var editingOutline: some View {
        if isEditingText {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(AppTheme.accent.opacity(0.9), lineWidth: 1.5)
                .padding(-8)
        }
    }

    private var sizeReader: some View {
        GeometryReader { proxy in
            Color.clear.preference(key: CaptionSizeKey.self, value: proxy.size)
        }
        .onPreferenceChange(CaptionSizeKey.self) { captionSize = $0 }
    }

    /// Once the caption is small it stops looking like something you can grab, so it
    /// is given a faint outline to aim at.
    @ViewBuilder
    private var smallCaptionHint: some View {
        if editing != nil, !isAdjusting, captionSize.height > 0, captionSize.height < 46 {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.white.opacity(0.22), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                .padding(-10)
        }
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

#if DEBUG
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
#endif

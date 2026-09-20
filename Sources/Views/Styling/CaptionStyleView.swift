import SwiftUI

/// Picks how subtitles look. Every change shows in the preview straight away.
struct CaptionStyleView: View {

    @Environment(\.dismiss) private var dismiss
    @Binding var style: CaptionStyle
    var sampleSegment: SubtitleSegment?

    /// Drives the karaoke preview so highlighting can be judged without playing.
    @State private var previewTime: TimeInterval = 0
    @State private var previewTimer: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    CaptionStylePreview(
                        style: style,
                        segment: sampleSegment ?? CaptionStylePreview.placeholder,
                        animatedTime: previewTime
                    )

                    presets
                    typography
                    colours
                    placement
                }
                .padding(.horizontal, 20)
                .padding(.top, 10)
                .padding(.bottom, 36)
            }
            .scrollIndicators(.hidden)
            .appBackground()
            .navigationTitle("Caption style")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .tint(AppTheme.accent)
                }
            }
        }
        .preferredColorScheme(.dark)
        .task { startPreviewLoop() }
        .onDisappear { previewTimer?.cancel() }
    }

    // MARK: - Presets

    private var presets: some View {
        section("Style") {
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    ForEach(CaptionStyle.Preset.allCases) { preset in
                        Button {
                            withAnimation(.snappy(duration: 0.2)) { style = .preset(preset) }
                        } label: {
                            Text(preset.displayName)
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(style.preset == preset ? .white : AppTheme.secondaryText)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .background {
                                    Capsule().fill(style.preset == preset ? AppTheme.accent : AppTheme.elevatedSurface)
                                }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 2)
            }
            .scrollIndicators(.hidden)
        }
    }

    // MARK: - Typography

    private var typography: some View {
        section("Text") {
            VStack(spacing: 14) {
                labelledPicker("Font", selection: $style.fontDesign) { design in
                    Text(design.displayName).tag(design)
                }

                labelledPicker("Weight", selection: $style.weight) { weight in
                    Text(weight.rawValue.capitalized).tag(weight)
                }

                slider(
                    "Size",
                    value: $style.referenceFontSize,
                    // Matches the bounds the pinch gesture enforces, so the slider and
                    // the fingers cannot disagree about the limits.
                    range: 24...140,
                    display: "\(Int(style.referenceFontSize))"
                )

                Toggle("Capital letters", isOn: $style.isUppercased)
                    .font(.footnote)
                    .tint(AppTheme.accent)

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Words on screen")
                            .font(.footnote)
                            .foregroundStyle(AppTheme.secondaryText)
                        Spacer()
                        Picker("Words on screen", selection: wordLimitBinding) {
                            Text("All").tag(0)
                            Text("6").tag(6)
                            Text("5").tag(5)
                            Text("4").tag(4)
                            Text("3").tag(3)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 210)
                    }
                    Text("Short bursts of words, the way short-form video captions read.")
                        .font(.caption2)
                        .foregroundStyle(AppTheme.tertiaryText)
                }
                .disabled(!hasWordTimings)
                .opacity(hasWordTimings ? 1 : 0.5)

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Spoken word")
                            .font(.footnote)
                            .foregroundStyle(AppTheme.secondaryText)
                        Spacer()
                        Picker("Spoken word", selection: $style.spokenWordEffect) {
                            ForEach(CaptionStyle.SpokenWordEffect.allCases) { effect in
                                Text(effect.displayName).tag(effect)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 190)
                    }
                    Text("Marks each word as it is spoken.")
                        .font(.caption2)
                        .foregroundStyle(AppTheme.tertiaryText)
                }
                .disabled(!hasWordTimings)
                .opacity(hasWordTimings ? 1 : 0.5)

                if !hasWordTimings {
                    Text("This subtitle has no word timings, so highlighting is unavailable.")
                        .font(.caption2)
                        .foregroundStyle(AppTheme.tertiaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    /// The picker works in Ints because a segmented control cannot tag nil; 0 is
    /// the "all words" case.
    private var wordLimitBinding: Binding<Int> {
        Binding(
            get: { style.maxWordsOnScreen ?? 0 },
            set: { style.maxWordsOnScreen = $0 == 0 ? nil : $0 }
        )
    }

    private var hasWordTimings: Bool {
        (sampleSegment ?? CaptionStylePreview.placeholder).words?.isEmpty == false
    }

    // MARK: - Colour

    private var colours: some View {
        section("Colour") {
            VStack(alignment: .leading, spacing: 14) {
                swatches(title: "Text", selection: $style.textColor)

                if style.spokenWordEffect == .colour {
                    swatches(title: "Spoken word", selection: $style.highlightColor)
                }

                if style.spokenWordEffect == .box {
                    swatches(title: "Spoken word box", selection: $style.spokenWordBackgroundColor)
                }

                labelledPicker("Behind", selection: $style.background) { background in
                    Text(background.displayName).tag(background)
                }

                if style.background == .block || style.background == .roundedBlock {
                    swatches(title: "Background", selection: $style.backgroundColor, usesOpacity: true)
                }
            }
        }
    }

    private func swatches(title: String, selection: Binding<CaptionColor>, usesOpacity: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundStyle(AppTheme.secondaryText)

            HStack(spacing: 10) {
                ForEach(Array(CaptionColor.palette.enumerated()), id: \.offset) { _, colour in
                    let resolved = usesOpacity ? colour.withOpacity(0.72) : colour
                    Button {
                        selection.wrappedValue = resolved
                    } label: {
                        Circle()
                            .fill(colour.color)
                            .frame(width: 30, height: 30)
                            .overlay {
                                Circle().strokeBorder(
                                    isSelected(resolved, selection.wrappedValue) ? AppTheme.accent : Color.white.opacity(0.25),
                                    lineWidth: isSelected(resolved, selection.wrappedValue) ? 3 : 1
                                )
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func isSelected(_ a: CaptionColor, _ b: CaptionColor) -> Bool {
        abs(a.red - b.red) < 0.01 && abs(a.green - b.green) < 0.01 && abs(a.blue - b.blue) < 0.01
    }

    // MARK: - Placement

    private var placement: some View {
        section("Placement") {
            VStack(spacing: 14) {
                slider(
                    "Height",
                    value: $style.verticalPosition,
                    range: 0.3...0.97,
                    display: "\(Int(style.verticalPosition * 100))%"
                )

                HStack {
                    Text("Position")
                        .font(.footnote)
                        .foregroundStyle(AppTheme.secondaryText)
                    Spacer()
                    Button {
                        withAnimation(.snappy(duration: 0.2)) {
                            style.horizontalPosition = 0.5
                            style.verticalPosition = 0.86
                        }
                    } label: {
                        Label("Reset", systemImage: "arrow.counterclockwise")
                            .font(.caption.weight(.medium))
                    }
                    .tint(AppTheme.accent)
                }

                Text("Drag the caption on the video to place it, or pinch to resize.")
                    .font(.caption2)
                    .foregroundStyle(AppTheme.tertiaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack {
                    Text("Alignment")
                        .font(.footnote)
                        .foregroundStyle(AppTheme.secondaryText)
                    Spacer()
                    Picker("Alignment", selection: $style.alignment) {
                        ForEach(CaptionStyle.TextAlignment.allCases) { alignment in
                            Image(systemName: alignment.symbolName).tag(alignment)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 170)
                }
            }
        }
    }

    // MARK: - Building blocks

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background {
            AppTheme.cardShape(AppTheme.controlRadius).fill(AppTheme.elevatedSurface)
        }
    }

    private func labelledPicker<T: Hashable, Content: View>(
        _ title: String,
        selection: Binding<T>,
        @ViewBuilder options: @escaping (T) -> Content
    ) -> some View where T: CaseIterable, T.AllCases: RandomAccessCollection {
        HStack {
            Text(title)
                .font(.footnote)
                .foregroundStyle(AppTheme.secondaryText)
            Spacer()
            Picker(title, selection: selection) {
                ForEach(Array(T.allCases), id: \.self) { value in
                    options(value)
                }
            }
            .tint(AppTheme.accent)
        }
    }

    private func slider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, display: String) -> some View {
        VStack(spacing: 4) {
            HStack {
                Text(title)
                    .font(.footnote)
                    .foregroundStyle(AppTheme.secondaryText)
                Spacer()
                Text(display)
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.white)
            }
            Slider(value: value, in: range)
                .tint(AppTheme.accent)
        }
    }

    // MARK: - Preview animation

    private func startPreviewLoop() {
        previewTimer?.cancel()
        previewTimer = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(120))
                guard !Task.isCancelled else { return }
                let span = (sampleSegment ?? CaptionStylePreview.placeholder).duration
                previewTime = span > 0 ? (previewTime + 0.12).truncatingRemainder(dividingBy: span) : 0
            }
        }
    }
}

#Preview {
    CaptionStyleView(style: .constant(.preset(.karaoke)), sampleSegment: nil)
}

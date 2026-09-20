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
    /// Supply this and the caption becomes an editable field in place, styled exactly
    /// as it is drawn, so what is typed is what will be seen.
    var editingText: Binding<String>?
    /// Called when the field gives up focus, so the caller can leave editing mode.
    var onEndEditing: (() -> Void)?

    @FocusState private var isFieldFocused: Bool

    private var fontSize: CGFloat {
        let size = style.fontSize(forFrameHeight: frameHeight)
        // Typing needs to be legible. Below this the caption is smaller than any text
        // anyone could read while editing it, so the field alone is floored.
        return editingText == nil ? size : max(size, 13)
    }

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
        if let editingText {
            TextField("Subtitle", text: editingText, axis: .vertical)
                .textFieldStyle(.plain)
                .foregroundStyle(style.textColor.color)
                .multilineTextAlignment(style.alignment.swiftUI)
                .lineSpacing(fontSize * 0.12)
                .lineLimit(1...4)
                .autocorrectionDisabled()
                .fixedSize(horizontal: false, vertical: true)
                .focused($isFieldFocused)
                .onAppear { isFieldFocused = true }
                .onChange(of: isFieldFocused) { _, focused in
                    if !focused { onEndEditing?() }
                }
                .toolbar {
                    ToolbarItemGroup(placement: .keyboard) {

                        Button {
                            editingText.wrappedValue = SubtitleSegmenter.splitInTwo(
                                editingText.wrappedValue.replacingOccurrences(of: "\n", with: " ")
                            )
                        } label: {
                            Label("Split in two", systemImage: "text.append").font(.body)
                        }
                        .disabled(editingText.wrappedValue.split(separator: " ").count < 2)

                        Button {
                            editingText.wrappedValue = editingText.wrappedValue
                                .replacingOccurrences(of: "\n", with: " ")
                        } label: {
                            Label("One line", systemImage: "text.aligncenter").font(.body)
                        }
                        .disabled(!editingText.wrappedValue.contains("\n"))

                        Spacer()

                        Button {
                            isFieldFocused = false
                        } label: {
                            // Stated explicitly: the caption's font is in the
                            // environment here, and the bar would grow with it.
                            Text("Done").font(.body.weight(.semibold))
                        }
                    }
                }
        } else if needsPerWordRendering {
            // One row per line the user wrote, so a hand-placed break survives even
            // when words are drawn individually for highlighting.
            VStack(alignment: stackAlignment, spacing: fontSize * 0.1) {
                ForEach(Array(wordLines.enumerated()), id: \.offset) { _, line in
                    CaptionFlowLayout(
                        alignment: style.alignment,
                        spacing: fontSize * 0.04,
                        lineSpacing: fontSize * 0.1
                    ) {
                        ForEach(line) { word in
                            wordView(word)
                        }
                    }
                }
            }
        } else {
            Text(display(segment.text))
                .foregroundStyle(style.textColor.color)
                .multilineTextAlignment(style.alignment.swiftUI)
                .lineSpacing(fontSize * 0.12)
        }
    }

    private var stackAlignment: HorizontalAlignment {
        switch style.alignment {
        case .leading: return .leading
        case .center: return .center
        case .trailing: return .trailing
        }
    }

    /// Groups the words into the lines the text is broken into.
    ///
    /// The words carry timings but no notion of layout, so the line structure comes
    /// from the text: each line takes as many words as it has. If the two disagree -
    /// after heavy retyping, say - everything left over joins the last line rather
    /// than being dropped.
    private var wordLines: [[SubtitleWord]] {
        guard let words = segment.words, !words.isEmpty else { return [] }

        let lines = segment.text
            .components(separatedBy: "\n")
            .map { $0.split(separator: " ").count }
            .filter { $0 > 0 }

        guard lines.count > 1 else { return [words] }

        var result: [[SubtitleWord]] = []
        var index = 0
        for count in lines {
            guard index < words.count else { break }
            let end = min(index + count, words.count)
            result.append(Array(words[index..<end]))
            index = end
        }
        if index < words.count, !result.isEmpty {
            result[result.count - 1].append(contentsOf: words[index...])
        }
        return result
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

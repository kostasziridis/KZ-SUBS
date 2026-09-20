import SwiftUI

/// Edits one subtitle: its words and its timing.
struct SubtitleEditSheet: View {

    @Environment(\.dismiss) private var dismiss

    let segment: SubtitleSegment
    var canGoPrevious: Bool
    var canGoNext: Bool
    var onChange: (SubtitleSegment) -> Void
    var onDelete: () -> Void
    var onPrevious: () -> Void
    var onNext: () -> Void
    var onSeek: (TimeInterval) -> Void

    @State private var text: String = ""
    @State private var startTime: TimeInterval = 0
    @State private var endTime: TimeInterval = 0
    @State private var words: [SubtitleWord] = []
    @State private var selectedWordID: SubtitleWord.ID?
    @FocusState private var isEditingText: Bool

    private let nudge: TimeInterval = 0.1

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    textCard
                    if !words.isEmpty { wordColourCard }
                    timingCard
                    navigationRow
                    deleteButton
                }
                .padding(.horizontal, 20)
                .padding(.top, 10)
                .padding(.bottom, 30)
            }
            .scrollIndicators(.hidden)
            .appBackground()
            .navigationTitle("Edit subtitle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .tint(AppTheme.accent)
                }
            }
        }
        .preferredColorScheme(.dark)
        .task(id: segment.id) { load() }
    }

    // MARK: - Text

    private var textCard: some View {
        GlassCard(radius: AppTheme.controlRadius, padding: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Text")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.tertiaryText)

                TextField("Subtitle text", text: $text, axis: .vertical)
                    .font(.body)
                    .foregroundStyle(.white)
                    .lineLimit(2...5)
                    .focused($isEditingText)
                    .onChange(of: text) { _, _ in commit() }

                HStack(spacing: 10) {
                    Button {
                        // Break it where the two lines come out closest in length.
                        text = SubtitleSegmenter.splitInTwo(text.replacingOccurrences(of: "\n", with: " "))
                        commit()
                    } label: {
                        Label("Split in two", systemImage: "text.append")
                            .font(.caption.weight(.medium))
                    }
                    .disabled(text.split(separator: " ").count < 2)

                    Button {
                        text = text.replacingOccurrences(of: "\n", with: " ")
                        commit()
                    } label: {
                        Label("One line", systemImage: "text.aligncenter")
                            .font(.caption.weight(.medium))
                    }
                    .disabled(!text.contains("\n"))
                }
                .tint(AppTheme.accent)

                Text("Return starts a new line. Two short lines read best.")
                    .font(.caption2)
                    .foregroundStyle(AppTheme.tertiaryText)
            }
        }
    }

    // MARK: - Word colours

    /// Colour one word on its own, for emphasis - independent of the caption style.
    private var wordColourCard: some View {
        GlassCard(radius: AppTheme.controlRadius, padding: 16) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Colour a word")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.tertiaryText)

                FlowRow(spacing: 8) {
                    ForEach(words) { word in
                        Button {
                            selectedWordID = selectedWordID == word.id ? nil : word.id
                        } label: {
                            Text(word.word)
                                .font(.footnote.weight(.medium))
                                .foregroundStyle(word.colorOverride?.color ?? .white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background {
                                    Capsule().fill(
                                        selectedWordID == word.id
                                            ? AppTheme.accent.opacity(0.28)
                                            : AppTheme.elevatedSurface
                                    )
                                }
                                .overlay {
                                    Capsule().strokeBorder(
                                        selectedWordID == word.id ? AppTheme.accent : .clear,
                                        lineWidth: 1.5
                                    )
                                }
                        }
                        .buttonStyle(.plain)
                    }
                }

                if let selectedWordID, let index = words.firstIndex(where: { $0.id == selectedWordID }) {
                    HStack(spacing: 10) {
                        ForEach(Array(CaptionColor.palette.enumerated()), id: \.offset) { _, colour in
                            Button {
                                words[index].colorOverride = colour
                                commit()
                            } label: {
                                Circle()
                                    .fill(colour.color)
                                    .frame(width: 28, height: 28)
                                    .overlay { Circle().strokeBorder(.white.opacity(0.25), lineWidth: 1) }
                            }
                            .buttonStyle(.plain)
                        }

                        Button {
                            words[index].colorOverride = nil
                            commit()
                        } label: {
                            Image(systemName: "arrow.uturn.backward")
                                .font(.caption.weight(.bold))
                                .frame(width: 28, height: 28)
                                .background { Circle().fill(AppTheme.elevatedSurface) }
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.white)
                    }
                } else {
                    Text("Tap a word, then pick a colour.")
                        .font(.caption2)
                        .foregroundStyle(AppTheme.tertiaryText)
                }
            }
        }
    }

    // MARK: - Timing

    private var timingCard: some View {
        GlassCard(radius: AppTheme.controlRadius, padding: 16) {
            VStack(spacing: 14) {
                timeRow(
                    label: "Start",
                    value: startTime,
                    onChange: { delta in
                        startTime = max(0, min(startTime + delta, endTime - 0.2))
                        onSeek(startTime)
                        commit()
                    }
                )

                Divider().overlay(AppTheme.hairline)

                timeRow(
                    label: "End",
                    value: endTime,
                    onChange: { delta in
                        endTime = max(startTime + 0.2, endTime + delta)
                        onSeek(endTime)
                        commit()
                    }
                )

                Divider().overlay(AppTheme.hairline)

                HStack {
                    Text("Duration")
                        .font(.footnote)
                        .foregroundStyle(AppTheme.secondaryText)
                    Spacer()
                    Text(String(format: "%.2fs", max(0, endTime - startTime)))
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(durationWarning == nil ? .white : .orange)
                }

                if let durationWarning {
                    Text(durationWarning)
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    /// Flags timings that will read badly, without preventing them.
    private var durationWarning: String? {
        let duration = endTime - startTime
        if duration < 0.8 { return "Very short — this may flash by too quickly to read." }
        if duration > 7 { return "Very long — consider splitting this subtitle." }
        return nil
    }

    private func timeRow(label: String, value: TimeInterval, onChange: @escaping (TimeInterval) -> Void) -> some View {
        HStack(spacing: 14) {
            Text(label)
                .font(.footnote)
                .foregroundStyle(AppTheme.secondaryText)
                .frame(width: 44, alignment: .leading)

            Text(TimecodeFormatter.precise(value))
                .font(.body.monospacedDigit().weight(.medium))
                .foregroundStyle(.white)

            Spacer()

            HStack(spacing: 8) {
                nudgeButton(symbol: "minus", action: { onChange(-nudge) })
                nudgeButton(symbol: "plus", action: { onChange(nudge) })
            }
        }
    }

    private func nudgeButton(symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.footnote.weight(.bold))
                .frame(width: 34, height: 30)
                .background {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(AppTheme.elevatedSurface)
                }
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
    }

    // MARK: - Navigation

    private var navigationRow: some View {
        HStack(spacing: 12) {
            Button(action: onPrevious) {
                Label("Previous", systemImage: "chevron.left")
                    .font(.footnote.weight(.medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(AppTheme.elevatedSurface)
                    }
            }
            .disabled(!canGoPrevious)
            .opacity(canGoPrevious ? 1 : 0.4)

            Button(action: onNext) {
                Label("Next", systemImage: "chevron.right")
                    .font(.footnote.weight(.medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(AppTheme.elevatedSurface)
                    }
            }
            .disabled(!canGoNext)
            .opacity(canGoNext ? 1 : 0.4)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
    }

    private var deleteButton: some View {
        Button(role: .destructive) {
            onDelete()
            dismiss()
        } label: {
            Label("Delete subtitle", systemImage: "trash")
                .font(.footnote.weight(.medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
        }
        .tint(.red)
    }

    // MARK: - State

    private func load() {
        text = segment.text
        startTime = segment.startTime
        endTime = segment.endTime
        words = segment.words ?? []
        selectedWordID = nil
    }

    private func commit() {
        var edited = segment
        edited.text = text
        edited.startTime = startTime
        edited.endTime = endTime
        // Only carry word timings back if they are still the ones this subtitle had;
        // retyping the text does not re-time the words.
        edited.words = words.isEmpty ? nil : words
        onChange(edited)
    }
}

#Preview {
    SubtitleEditSheet(
        segment: SubtitleSegment.samples[1],
        canGoPrevious: true,
        canGoNext: true,
        onChange: { _ in }, onDelete: {}, onPrevious: {}, onNext: {}, onSeek: { _ in }
    )
}

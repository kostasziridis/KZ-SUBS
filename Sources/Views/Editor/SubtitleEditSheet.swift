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
    /// The words as the speech engine timed them, kept aside so that retyping the text
    /// is always matched against the original rather than against the last match.
    /// Without it, typing a word one letter at a time would walk the timings away.
    @State private var baselineWords: [SubtitleWord] = []
    @State private var selectedWordID: SubtitleWord.ID?
    @State private var draftWord: String = ""
    /// Words the dictionary does not have. Spelling only - a correctly spelled word in
    /// the wrong place is not something any dictionary can see.
    @State private var misspelled: Set<String> = []
    @State private var suggestions: [String] = []
    @FocusState private var isEditingText: Bool
    @FocusState private var isEditingWord: Bool

    private let nudge: TimeInterval = 0.1

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    textCard
                    if !words.isEmpty { wordCard }
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
        .task(id: words.map(\.word).joined(separator: " ")) { await checkSpelling() }
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
                    .onChange(of: text) { _, _ in applyTextEdit() }

                HStack(spacing: 10) {
                    Button {
                        // Break it where the two lines come out closest in length.
                        text = SubtitleSegmenter.splitInTwo(text.replacingOccurrences(of: "\n", with: " "))
                        applyTextEdit()
                    } label: {
                        Label("Split in two", systemImage: "text.append")
                            .font(.caption.weight(.medium))
                    }
                    .disabled(text.split(separator: " ").count < 2)

                    Button {
                        text = text.replacingOccurrences(of: "\n", with: " ")
                        applyTextEdit()
                    } label: {
                        Label("One line", systemImage: "text.aligncenter")
                            .font(.caption.weight(.medium))
                    }
                    .disabled(!text.contains("\n"))
                }
                .tint(AppTheme.accent)

                // The two editors do different jobs, and nothing said so: this one
                // changes which words there are, the one below changes one word.
                Text(words.isEmpty
                     ? "Return starts a new line. Two short lines read best."
                     : "Add or remove words here, or press Return for a new line.")
                    .font(.caption2)
                    .foregroundStyle(AppTheme.tertiaryText)
            }
        }
    }

    // MARK: - Words

    /// One word at a time: correct its spelling, or colour it on its own.
    ///
    /// This is the only place a word can be changed without disturbing anything else.
    /// Each word keeps the moment it was spoken, so the caption styles that light up
    /// words one by one carry on working after a correction.
    private var wordCard: some View {
        GlassCard(radius: AppTheme.controlRadius, padding: 16) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Words")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.tertiaryText)

                FlowRow(spacing: 8) {
                    ForEach(words) { word in
                        Button {
                            select(word)
                        } label: {
                            Text(word.word)
                                .font(.footnote.weight(.medium))
                                .foregroundStyle(word.colorOverride?.color ?? .white)
                                // Marked rather than corrected: the dictionary is not
                                // sure enough to change anyone's words for them.
                                .underline(misspelled.contains(word.word), pattern: .dot, color: .orange)
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

                if let index = selectedIndex {
                    selectedWordEditor(at: index)
                } else {
                    Text(misspelled.isEmpty
                         ? "Tap a word to correct its spelling or colour it. Its timing stays put."
                         : "Underlined words are not in the dictionary. Tap one to see suggestions.")
                        .font(.caption2)
                        .foregroundStyle(AppTheme.tertiaryText)
                }
            }
        }
    }

    private var selectedIndex: Int? {
        guard let selectedWordID else { return nil }
        return words.firstIndex { $0.id == selectedWordID }
    }

    @ViewBuilder
    private func selectedWordEditor(at index: Int) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider().overlay(AppTheme.hairline)

            HStack(spacing: 10) {
                TextField("Word", text: $draftWord)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.white)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .focused($isEditingWord)
                    .onSubmit { commitDraftWord() }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(AppTheme.elevatedSurface)
                    }

                Button("Apply") { commitDraftWord() }
                    .font(.footnote.weight(.semibold))
                    .tint(AppTheme.accent)
                    .disabled(draftWord.trimmingCharacters(in: .whitespaces).isEmpty
                              || draftWord == words[index].word)
            }

            if !suggestions.isEmpty {
                FlowRow(spacing: 8) {
                    ForEach(suggestions, id: \.self) { suggestion in
                        Button {
                            draftWord = suggestion
                            commitDraftWord()
                        } label: {
                            Text(suggestion)
                                .font(.footnote.weight(.medium))
                                .foregroundStyle(AppTheme.accent)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background { Capsule().fill(AppTheme.accent.opacity(0.16)) }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Text("Spoken at \(TimecodeFormatter.precise(words[index].startTime)) — unchanged by a correction.")
                .font(.caption2)
                .foregroundStyle(AppTheme.tertiaryText)

            HStack(spacing: 10) {
                CaptionColorPalette(
                    selection: Binding(
                        get: { words[index].colorOverride ?? .white },
                        set: { setColour($0, at: index) }
                    )
                )

                Button {
                    setColour(nil, at: index)
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.caption.weight(.bold))
                        .frame(width: 28, height: 28)
                        .background { Circle().fill(AppTheme.elevatedSurface) }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
            }
        }
    }

    // MARK: - Word editing

    private func select(_ word: SubtitleWord) {
        if selectedWordID == word.id {
            selectedWordID = nil
            isEditingWord = false
            suggestions = []
        } else {
            selectedWordID = word.id
            draftWord = word.word
            suggestions = []
            guard misspelled.contains(word.word) else { return }
            Task {
                let found = await SpellCheck.suggestions(for: word.word)
                // The user may have moved on while the dictionary was being searched.
                guard selectedWordID == word.id else { return }
                suggestions = found
            }
        }
    }

    private func checkSpelling() async {
        guard !words.isEmpty else {
            misspelled = []
            return
        }
        misspelled = await SpellCheck.unknownWords(in: words.map(\.word))
    }

    private func commitDraftWord() {
        guard let selectedWordID else { return }
        let trimmed = draftWord.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            // Put the word back rather than leaving an empty box: deleting a word is
            // what the text field above is for.
            draftWord = words.first { $0.id == selectedWordID }?.word ?? ""
            return
        }

        var draft = draftSegment()
        draft.renameWord(id: selectedWordID, to: trimmed)

        words = draft.words ?? words
        mirrorIntoBaseline()
        // Set last: the text field watches this, and the baseline has to agree with it
        // first or the edit would immediately be re-matched away.
        text = draft.text
        draftWord = words.first { $0.id == selectedWordID }?.word ?? trimmed

        onChange(draft)
        isEditingWord = false
        suggestions = []
    }

    private func setColour(_ colour: CaptionColor?, at index: Int) {
        words[index].colorOverride = colour
        mirrorIntoBaseline()
        commit()
    }

    /// Keeps the untouched original in step with deliberate word edits, so that a later
    /// correction in the text field does not undo them.
    private func mirrorIntoBaseline() {
        for word in words {
            guard let index = baselineWords.firstIndex(where: { $0.id == word.id }) else { continue }
            baselineWords[index].word = word.word
            baselineWords[index].colorOverride = word.colorOverride
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
        if duration < 0.8 { return String(localized: "Very short — this may flash by too quickly to read.") }
        if duration > 7 { return String(localized: "Very long — consider splitting this subtitle.") }
        return nil
    }

    private func timeRow(label: LocalizedStringKey, value: TimeInterval, onChange: @escaping (TimeInterval) -> Void) -> some View {
        HStack(spacing: 14) {
            Text(label)
                .font(.footnote)
                .foregroundStyle(AppTheme.secondaryText)
                // Wide enough for a Greek word: "Έναρξη" broke across two lines in
                // the 44pt box that fitted "Start".
                .fixedSize()
                .frame(width: 66, alignment: .leading)

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
        baselineWords = words
        selectedWordID = nil
        draftWord = ""
    }

    /// The subtitle as the sheet currently has it.
    private func draftSegment() -> SubtitleSegment {
        var edited = segment
        edited.text = text
        edited.startTime = startTime
        edited.endTime = endTime
        edited.words = words.isEmpty ? nil : words
        return edited
    }

    /// Carries a change made in the text field into the timed words.
    ///
    /// Always matched against `baselineWords`, never against the last result: matching
    /// against the last result would let a half-typed word throw away a timing that the
    /// finished word should have got back.
    private func applyTextEdit() {
        guard !baselineWords.isEmpty else {
            commit()
            return
        }

        // Line breaks and punctuation are not words, so there is nothing to re-match
        // when they are all that changed.
        guard WordAligner.tokenise(text) != words.map(\.word) else {
            commit()
            return
        }

        words = WordAligner.realign(
            text: text,
            to: baselineWords,
            start: startTime,
            end: endTime
        )
        if selectedIndex == nil { selectedWordID = nil }
        commit()
    }

    private func commit() {
        onChange(draftSegment())
    }
}
#if DEBUG
#Preview {
    SubtitleEditSheet(
        segment: SubtitleSegment.samples[1],
        canGoPrevious: true,
        canGoNext: true,
        onChange: { _ in }, onDelete: {}, onPrevious: {}, onNext: {}, onSeek: { _ in }
    )
}
#endif

import Foundation

/// A single spoken word with its own timing.
///
/// Word timings are kept even when the UI does not use them yet: they are what makes
/// karaoke-style highlighting possible later without re-transcribing anything.
struct SubtitleWord: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    var word: String
    // Not constants: correcting the text can move a word a little, and a word written
    // in where there was none has to be given a moment of its own.
    var startTime: TimeInterval
    var endTime: TimeInterval
    /// Set by hand to colour this one word, overriding the style. Nil follows the style.
    var colorOverride: CaptionColor?

    init(
        id: UUID = UUID(),
        word: String,
        startTime: TimeInterval,
        endTime: TimeInterval,
        colorOverride: CaptionColor? = nil
    ) {
        self.id = id
        self.word = word
        self.startTime = startTime
        self.endTime = endTime
        self.colorOverride = colorOverride
    }
}

/// One subtitle block as it appears on screen.
struct SubtitleSegment: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    var startTime: TimeInterval
    var endTime: TimeInterval
    var text: String
    var words: [SubtitleWord]?

    init(
        id: UUID = UUID(),
        startTime: TimeInterval,
        endTime: TimeInterval,
        text: String,
        words: [SubtitleWord]? = nil
    ) {
        self.id = id
        self.startTime = startTime
        self.endTime = endTime
        self.text = text
        self.words = words
    }


    // MARK: - Editing

    /// Replaces the text and carries the correction into the timed words.
    ///
    /// Karaoke and spoken-word styles draw the caption from `words`, so setting `text`
    /// on its own leaves a misspelling on screen even though the list shows it fixed.
    /// This keeps the two in step, and `WordAligner` keeps each word's measured timing
    /// with it while it does.
    mutating func setText(_ newText: String) {
        text = newText

        // No timings to begin with - nothing to keep in step, and inventing some would
        // only turn an honest plain caption into a guessed karaoke one.
        guard let existing = words, !existing.isEmpty else { return }

        let realigned = WordAligner.realign(
            text: newText,
            to: existing,
            start: startTime,
            end: endTime
        )
        words = realigned.isEmpty ? nil : realigned
    }

    /// Respells one word, leaving its timing and every other word untouched.
    ///
    /// The precise tool: nothing is matched or guessed, because the word being changed
    /// is named outright.
    mutating func renameWord(id wordID: SubtitleWord.ID, to newWord: String) {
        guard var updated = words, let index = updated.firstIndex(where: { $0.id == wordID }) else { return }

        let trimmed = newWord.trimmingCharacters(in: .whitespacesAndNewlines)
        // A word typed down to nothing would leave a gap in the caption and an
        // untypeable chip. Refuse rather than delete something by accident.
        guard !trimmed.isEmpty else { return }
        // Spaces would silently become two words with one timing between them.
        updated[index].word = trimmed.replacingOccurrences(of: " ", with: "")

        words = updated
        text = Self.rebuildText(text, replacingWordAt: index, with: updated[index].word, allWords: updated)
    }

    /// Puts the corrected word back into the text without losing the user's line breaks.
    private static func rebuildText(
        _ text: String,
        replacingWordAt index: Int,
        with replacement: String,
        allWords: [SubtitleWord]
    ) -> String {
        let lines = text.components(separatedBy: "\n").map { WordAligner.tokenise($0) }
        let total = lines.reduce(0) { $0 + $1.count }

        // The text and the words have drifted apart - after heavy retyping, say. The
        // words are the truth here, so rebuild from them and accept losing the breaks.
        guard total == allWords.count, index < total else {
            return allWords.map(\.word).joined(separator: " ")
        }

        var remaining = index
        var rebuilt: [[String]] = []
        for var line in lines {
            if remaining >= 0, remaining < line.count {
                line[remaining] = replacement
            }
            remaining -= line.count
            rebuilt.append(line)
        }
        return rebuilt.map { $0.joined(separator: " ") }.joined(separator: "\n")
    }

    var duration: TimeInterval { max(0, endTime - startTime) }

    func contains(_ time: TimeInterval) -> Bool {
        time >= startTime && time < endTime
    }

    /// The word being spoken at `time`, when word timings are available.
    func word(at time: TimeInterval) -> SubtitleWord? {
        words?.first { time >= $0.startTime && time < $0.endTime }
    }
}

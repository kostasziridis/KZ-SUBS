import Foundation

/// Removes the subtitling credits speech engines invent out of nothing.
///
/// Whisper learned from subtitle files, and a great many of those end with a line
/// naming whoever made them. Over silence, music or noise it will sometimes write one
/// of those lines out - "Υπότιτλοι AUTHORWAVE", "Subtitles by the Amara.org community"
/// - with the same confidence it has in real speech. That confidence is why the
/// engine's own thresholds never catch it: to the model this is not a guess.
///
/// So it is caught here instead, by what it says rather than how sure the engine was.
/// A credit is a narrow, recognisable thing, and everything this looks for is text
/// that only ever appears in one: a subtitling house's name, or a line that opens by
/// announcing who did the subtitling. Anything wider would start deleting speech.
///
/// It is cut out word by word rather than a subtitle at a time, because the invented
/// line does not always arrive alone. Real output has it running straight into the
/// sentence that follows - "Υπότιτλοι AUTHORWAVE Στην AgroTech," - and dropping the
/// whole subtitle there would throw away words that were actually spoken.
enum HallucinatedCredits {

    // MARK: - Filtering

    /// The segment with any invented credit taken out, or `nil` if that was all it was.
    static func strip(_ segment: SubtitleSegment) -> SubtitleSegment? {
        let parts = sentences(in: segment.text)

        var dropped = Set<Int>()
        var rebuilt: [String] = []
        var offset = 0

        for part in parts {
            let tokens = WordAligner.tokenise(part)
            guard let credit = creditRange(in: tokens) else {
                rebuilt.append(part)
                offset += tokens.count
                continue
            }

            credit.forEach { dropped.insert(offset + $0) }
            let kept = tokens.enumerated().filter { !credit.contains($0.offset) }.map(\.element)
            // Keep whatever space stood before this sentence, so removing a credit from
            // the middle of a line does not run two sentences together.
            let leading = String(part.prefix(while: \.isWhitespace))
            rebuilt.append(kept.isEmpty ? "" : leading + kept.joined(separator: " "))
            offset += tokens.count
        }

        guard !dropped.isEmpty else { return segment }
        AppLog.speech.notice("Removed an invented subtitling credit")

        let text = rebuilt.joined()
            .replacingOccurrences(of: " +", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        var trimmed = segment
        // The words that went with the credit are found by counting, not by guesswork:
        // their positions in the text are exactly the positions just removed. Only when
        // text and words have drifted apart does this fall back to alignment.
        if let words = segment.words, words.count == offset {
            let surviving = words.enumerated().filter { !dropped.contains($0.offset) }.map(\.element)
            guard let first = surviving.first, let last = surviving.last else { return nil }
            trimmed.text = text
            trimmed.words = surviving
            // Pull the subtitle in around what is left, so it does not sit on screen
            // through the silence the credit was hallucinated from.
            trimmed.startTime = first.startTime
            trimmed.endTime = last.endTime
        } else {
            trimmed.setText(text)
        }
        return trimmed
    }

    // MARK: - Recognising a credit

    /// Which words of a sentence are a subtitling credit, if any.
    static func creditRange(in tokens: [String]) -> Range<Int>? {
        let folded = tokens.map { token in
            GreekSpellChecker.fold(token)
                .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
                .joined(separator: " ")
        }
        guard folded.contains(where: { !$0.isEmpty }) else { return nil }

        // A subtitling house's name is the one certain marker, and it gives the credit
        // a precise edge: grow outwards from it only over words that belong to a
        // credit, and stop the moment speech begins.
        if let anchor = folded.firstIndex(where: { name in studios.contains { name.contains($0) } }) {
            var start = anchor
            while start > 0, leadIn.contains(folded[start - 1]) || folded[start - 1].isEmpty {
                start -= 1
            }
            var end = anchor + 1
            while end < folded.count, tailEnd.contains(folded[end]) {
                end += 1
            }
            return start..<end
        }

        // With no name to anchor on, the whole sentence has to read as a credit: it
        // must open by saying who did the subtitling, and be as short as a credit is.
        // A sentence that merely mentions subtitles in passing runs longer and stays.
        let words = folded.filter { !$0.isEmpty }
        guard words.count <= maximumCreditWords else { return nil }
        let joined = words.joined(separator: " ")
        guard openings.contains(where: { joined == $0 || joined.hasPrefix("\($0) ") }) else { return nil }
        return 0..<tokens.count
    }

    /// Whether a whole sentence is a credit. The readable form of `creditRange`.
    static func isCredit(_ sentence: String) -> Bool {
        let tokens = WordAligner.tokenise(sentence)
        guard let range = creditRange(in: tokens) else { return false }
        return range.count == tokens.count
    }

    /// Longer than a credit line ever is, short enough that a real sentence about
    /// subtitling survives.
    private static let maximumCreditWords = 7

    /// Subtitling houses, accent-stripped and lowercased to match `fold`. Multi-word
    /// entries are spaced because punctuation is dropped: "amara.org" folds to two.
    private static let studios: Set<String> = [
        "authorwave",
        "amara org",
        "subs4free",
        "subztv",
        "subz tv",
        "opensubtitles",
        "addic7ed",
        "subscene",
        "vipsubs",
        "greeksubs",
        "subtitles gr",
        "subtitlesgr"
    ]

    /// Words a credit can run through on its way to the name, folded the same way.
    private static let leadIn: Set<String> = [
        "υποτιτλοι", "υποτιτλοσ", "υποτιτλων", "υποτιτλουσ", "υποτιτλισμοσ",
        "αποδοση", "διαλογων", "επιμελεια", "μεταφραση", "συγχρονισμοσ",
        "διανομη", "απο", "και",
        "subtitles", "subtitle", "subtitling", "subtitled", "captions", "captioned",
        "transcription", "transcribed", "translation", "translated",
        "sync", "synced", "corrections", "by", "the", "and", "from"
    ]

    /// Words a credit can trail off with after the name.
    private static let tailEnd: Set<String> = [
        "community", "team", "group", "subs", "ομαδα", "team gr"
    ]

    /// How a credit line opens when there is no name to anchor on, folded the same way.
    private static let openings: Set<String> = [
        // Greek
        "υποτιτλοι",
        "υποτιτλισμοσ",
        "υποτιτλισμοσ και αποδοση",
        "αποδοση διαλογων",
        "αποδοση υποτιτλων",
        "επιμελεια υποτιτλων",
        "μεταφραση υποτιτλων",
        "μεταφραση και υποτιτλισμοσ",
        "διανομη υποτιτλων",
        "συγχρονισμοσ υποτιτλων",
        // English
        "subtitles by",
        "subtitled by",
        "subtitling by",
        "captions by",
        "captioned by",
        "transcription by",
        "transcribed by",
        "translated by",
        "translation by",
        "sync by",
        "synced by",
        "subtitles and corrections by"
    ]

    // MARK: - Sentences

    /// Splits text into sentences, keeping every character exactly where it was so the
    /// survivors can be joined back together without reflowing anything.
    static func sentences(in text: String) -> [String] {
        // Greek writes a question with ";" and a semicolon with "·".
        let terminators: Set<Character> = [".", "!", "?", ";", "·", "…", "\n"]

        var result: [String] = []
        var current = ""

        var index = text.startIndex
        while index < text.endIndex {
            let character = text[index]
            current.append(character)
            let next = text.index(after: index)

            // Break after a run of terminators, so "..." does not become three
            // sentences and a trailing quote stays with the sentence it closes.
            if terminators.contains(character),
               next == text.endIndex || !terminators.contains(text[next]) {
                result.append(current)
                current = ""
            }
            index = next
        }

        if !current.isEmpty { result.append(current) }
        return result
    }
}

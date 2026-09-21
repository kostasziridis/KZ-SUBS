import Foundation

/// Keeps word timings attached to the right words after the text has been retyped.
///
/// Karaoke and spoken-word highlighting draw the caption from `words`, not from `text`
/// - each word has to be a separate view to be coloured on its own. So retyping the
/// text alone changes nothing on screen in those styles, and the fix is to carry the
/// edit into the words while keeping the timings the speech engine measured.
///
/// Correcting spelling or grammar is by far the common case, and it leaves the number
/// of words alone: "καλως" becomes "καλώς" in the same slot, at the same moment. That
/// case is matched exactly. Adding or removing words is rarer and cannot be timed
/// honestly, so those words borrow the space between the words around them.
enum WordAligner {

    /// Re-attaches `words` to a new piece of text.
    ///
    /// - Parameters:
    ///   - text: the edited text, line breaks and all.
    ///   - words: the words as they were, with their measured timings.
    ///   - start: the subtitle's own start, used when the text now begins with a word
    ///            that was not there before.
    ///   - end: likewise for the end.
    static func realign(
        text: String,
        to words: [SubtitleWord],
        start: TimeInterval,
        end: TimeInterval
    ) -> [SubtitleWord] {
        let tokens = tokenise(text)
        guard !tokens.isEmpty else { return [] }
        guard !words.isEmpty else { return spread(tokens, from: start, to: end) }

        let pairs = matchedPairs(tokens.map(comparable), words.map { comparable($0.word) })

        // Every new token, holding the old word it was recognised as - or nothing,
        // when it is a word the user has just written.
        var anchored: [SubtitleWord?] = Array(repeating: nil, count: tokens.count)
        var origins: [Int?] = Array(repeating: nil, count: tokens.count)
        for pair in pairs {
            var kept = words[pair.old]
            // Same word, respelled: the timing and any hand-picked colour stay with it.
            kept.word = tokens[pair.new]
            anchored[pair.new] = kept
            origins[pair.new] = pair.old
        }

        let filled = fillGaps(in: anchored, tokens: tokens, start: start, end: end)
        return closingGapsLeftByDeletions(
            in: filled,
            origins: origins,
            oldCount: words.count,
            start: start,
            end: end
        )
    }

    // MARK: - Tokens

    /// Splits on whitespace only. Line breaks are layout, and `CaptionBlockView`
    /// re-derives them from the text, so they must not become words here.
    static func tokenise(_ text: String) -> [String] {
        text.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    /// The form two words are compared in: accents and case are exactly what the user
    /// is here to correct, so they cannot be allowed to break the match. Punctuation
    /// goes too, so adding a comma does not orphan a word.
    private static func comparable(_ word: String) -> String {
        word
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "el"))
            .trimmingCharacters(in: .punctuationCharacters)
    }

    // MARK: - Matching

    private struct Pair {
        let new: Int
        let old: Int
    }

    /// Longest common subsequence, walked back into index pairs.
    ///
    /// Order matters and repeats are common ("και ... και"), so a positional match
    /// beats matching by name: it is what keeps the second "και" on the second timing.
    /// Subtitles are a handful of words, so the quadratic table costs nothing.
    private static func matchedPairs(_ new: [String], _ old: [String]) -> [Pair] {
        guard !new.isEmpty, !old.isEmpty else { return [] }

        var table = Array(
            repeating: Array(repeating: 0, count: old.count + 1),
            count: new.count + 1
        )

        for i in stride(from: new.count - 1, through: 0, by: -1) {
            for j in stride(from: old.count - 1, through: 0, by: -1) {
                table[i][j] = new[i] == old[j]
                    ? table[i + 1][j + 1] + 1
                    : max(table[i + 1][j], table[i][j + 1])
            }
        }

        var pairs: [Pair] = []
        var i = 0
        var j = 0
        while i < new.count, j < old.count {
            if new[i] == old[j] {
                pairs.append(Pair(new: i, old: j))
                i += 1
                j += 1
            } else if table[i + 1][j] >= table[i][j + 1] {
                i += 1
            } else {
                j += 1
            }
        }
        return pairs
    }

    // MARK: - Timing

    /// Gives the newly written words somewhere to live, between the words that kept
    /// their timings.
    ///
    /// Speech rarely leaves a gap to put them in - one word ends exactly where the next
    /// begins - so a run with nowhere to go borrows from the word after it. Sitting the
    /// new word on top of its neighbour instead would light both at once and hide the
    /// neighbour's own turn entirely.
    private static func fillGaps(
        in anchored: [SubtitleWord?],
        tokens: [String],
        start: TimeInterval,
        end: TimeInterval
    ) -> [SubtitleWord] {
        /// Short, but long enough to be seen passing.
        let minimumPerWord: TimeInterval = 0.12

        var result = anchored
        var index = 0

        while index < result.count {
            guard result[index] == nil else {
                index += 1
                continue
            }

            // How far the run of new words stretches, and what it is wedged between.
            var runEnd = index
            while runEnd < result.count, result[runEnd] == nil { runEnd += 1 }

            let count = runEnd - index
            let from = index > 0 ? (result[index - 1]?.endTime ?? start) : start
            var to = runEnd < result.count ? (result[runEnd]?.startTime ?? end) : end

            let needed = Double(count) * minimumPerWord
            if to - from < needed, runEnd < result.count, var next = result[runEnd] {
                // Take it out of the following word, never more than half of it: the
                // new word is spoken just before that one, so that is whose time it is.
                let borrow = min(needed - (to - from), (next.endTime - next.startTime) / 2)
                next.startTime += borrow
                result[runEnd] = next
                to = next.startTime
            }

            let filled = spread(Array(tokens[index..<runEnd]), from: from, to: max(from, to))
            for (offset, word) in filled.enumerated() {
                result[index + offset] = word
            }

            index = runEnd
        }

        return result.compactMap { $0 }
    }

    /// Stretches a word over the time a word deleted after it used to occupy.
    ///
    /// Otherwise deleting a word leaves the highlight sitting in the dark for as long
    /// as that word was spoken, which reads as a fault rather than as an edit.
    private static func closingGapsLeftByDeletions(
        in words: [SubtitleWord],
        origins: [Int?],
        oldCount: Int,
        start: TimeInterval,
        end: TimeInterval
    ) -> [SubtitleWord] {
        guard !words.isEmpty else { return words }
        var result = words

        for index in 0..<(result.count - 1) {
            guard let mine = origins[index], let next = origins[index + 1] else { continue }
            // Consecutive in the new text but not in the old: something was removed.
            if next > mine + 1 {
                result[index].endTime = result[index + 1].startTime
            }
        }

        if let first = origins.first ?? nil, first > 0 {
            result[0].startTime = min(result[0].startTime, start)
        }
        if let last = origins.last ?? nil, last < oldCount - 1 {
            result[result.count - 1].endTime = max(result[result.count - 1].endTime, end)
        }

        return result
    }

    /// Lays words out evenly over a span. A guess, but a visible one: the highlight
    /// still moves through them left to right at a steady pace.
    private static func spread(
        _ tokens: [String],
        from start: TimeInterval,
        to end: TimeInterval
    ) -> [SubtitleWord] {
        guard !tokens.isEmpty else { return [] }

        let step = max(end - start, 0) / Double(tokens.count)

        return tokens.enumerated().map { offset, token in
            SubtitleWord(
                word: token,
                startTime: start + Double(offset) * step,
                endTime: start + Double(offset + 1) * step
            )
        }
    }
}

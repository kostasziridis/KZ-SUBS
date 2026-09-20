import Foundation

/// Turns what the speech engine returns into subtitles a person can actually read.
///
/// The engine's own segments follow its decoding windows, not reading comfort: some
/// run for a paragraph, others for a word. This reshapes them, and is deliberately
/// independent of the engine so the rules can be tuned without touching transcription.
enum SubtitleSegmenter {

    /// Every tunable in one place.
    struct Rules: Sendable, Equatable {
        var maxLines: Int = 2
        var maxCharactersPerLine: Int = 42
        /// Below this, a line is short enough that we would rather merge than keep.
        var targetCharactersPerLine: Int = 36
        /// A subtitle flashing by faster than this is unreadable.
        var minimumDuration: TimeInterval = 1.0
        /// Longer than this and it has outstayed its welcome.
        var maximumDuration: TimeInterval = 6.0
        /// Two subtitles further apart than this are separate thoughts; never merge.
        var maximumMergeGap: TimeInterval = 0.4

        var maxCharacters: Int { maxLines * maxCharactersPerLine }

        static let `default` = Rules()
    }

    /// Reshapes raw engine output into readable subtitle blocks.
    static func makeSubtitles(from raw: [SubtitleSegment], rules: Rules = .default) -> [SubtitleSegment] {
        let cleaned = raw
            .map { normalise($0) }
            .filter { !$0.text.isEmpty }
            .sorted { $0.startTime < $1.startTime }

        guard !cleaned.isEmpty else { return [] }

        let split = cleaned.flatMap { splitIfTooLong($0, rules: rules) }
        let merged = mergeShortNeighbours(split, rules: rules)
        return merged.map { wrapLines($0, rules: rules) }
    }

    // MARK: - Cleaning

    private static func normalise(_ segment: SubtitleSegment) -> SubtitleSegment {
        var copy = segment
        copy.text = segment.text
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return copy
    }

    // MARK: - Splitting

    /// Breaks a segment that is too long to read, or too long to sit on screen.
    ///
    /// Only splits where word timings say it is safe: without them we cannot know when
    /// the second half starts, and a guessed timing is worse than a long subtitle.
    private static func splitIfTooLong(_ segment: SubtitleSegment, rules: Rules) -> [SubtitleSegment] {
        let needsSplit = segment.text.count > rules.maxCharacters || segment.duration > rules.maximumDuration
        guard needsSplit, let words = segment.words, words.count > 1 else { return [segment] }

        var result: [SubtitleSegment] = []
        var current: [SubtitleWord] = []

        func flush() {
            guard let first = current.first, let last = current.last else { return }
            result.append(
                SubtitleSegment(
                    startTime: first.startTime,
                    endTime: last.endTime,
                    text: current.map(\.word).joined(separator: " ").trimmingCharacters(in: .whitespaces),
                    words: current
                )
            )
            current = []
        }

        for word in words {
            let prospective = (current.map(\.word) + [word.word]).joined(separator: " ").count
            let prospectiveDuration = word.endTime - (current.first?.startTime ?? word.startTime)

            if !current.isEmpty, prospective > rules.maxCharacters || prospectiveDuration > rules.maximumDuration {
                flush()
            }

            current.append(word)

            // A sentence ending is the most natural place to break, so take it as soon
            // as the line is long enough to be worth keeping on its own.
            if endsSentence(word.word),
               current.map(\.word).joined(separator: " ").count >= rules.targetCharactersPerLine {
                flush()
            }
        }
        flush()

        return result.isEmpty ? [segment] : result
    }

    private static func endsSentence(_ word: String) -> Bool {
        guard let last = word.trimmingCharacters(in: .whitespaces).last else { return false }
        // Greek uses ";" as its question mark and "·" as a semicolon.
        return ".!?;·…".contains(last)
    }

    // MARK: - Merging

    /// Joins neighbours that are too brief to read on their own.
    private static func mergeShortNeighbours(_ segments: [SubtitleSegment], rules: Rules) -> [SubtitleSegment] {
        var result: [SubtitleSegment] = []

        for segment in segments {
            guard var previous = result.last else {
                result.append(segment)
                continue
            }

            let gap = segment.startTime - previous.endTime
            let combinedText = "\(previous.text) \(segment.text)"
            let combinedDuration = segment.endTime - previous.startTime

            let previousIsTooBrief = previous.duration < rules.minimumDuration
            let currentIsTooBrief = segment.duration < rules.minimumDuration

            let canMerge = (previousIsTooBrief || currentIsTooBrief)
                && gap >= 0 && gap <= rules.maximumMergeGap
                && combinedText.count <= rules.maxCharacters
                && combinedDuration <= rules.maximumDuration

            if canMerge {
                previous.endTime = segment.endTime
                previous.text = combinedText
                if let existing = previous.words, let incoming = segment.words {
                    previous.words = existing + incoming
                } else {
                    previous.words = nil
                }
                result[result.count - 1] = previous
            } else {
                result.append(segment)
            }
        }

        return result
    }

    // MARK: - Line wrapping

    /// Lays the text out over at most `maxLines`, balancing them so one line is not
    /// a lone word under a full one. Never breaks inside a word.
    static func wrapLines(_ segment: SubtitleSegment, rules: Rules = .default) -> SubtitleSegment {
        var copy = segment
        copy.text = wrap(segment.text, rules: rules)
        return copy
    }

    static func wrap(_ text: String, rules: Rules = .default) -> String {
        let words = text.split(separator: " ").map(String.init)
        guard words.count > 1, text.count > rules.maxCharactersPerLine else { return text }

        // Find the split point closest to the middle, so the two lines look balanced.
        let target = text.count / 2
        var best: (index: Int, distance: Int)?
        var runningLength = 0

        for index in 0..<(words.count - 1) {
            runningLength += words[index].count + (index == 0 ? 0 : 1)
            let distance = abs(runningLength - target)
            if best == nil || distance < best!.distance {
                best = (index, distance)
            }
        }

        guard let split = best else { return text }
        let first = words[0...split.index].joined(separator: " ")
        let second = words[(split.index + 1)...].joined(separator: " ")

        // If a balanced break still leaves an over-long line there is nothing more to
        // do here: the text is simply long, and splitting the segment is the fix.
        return "\(first)\n\(second)"
    }
}

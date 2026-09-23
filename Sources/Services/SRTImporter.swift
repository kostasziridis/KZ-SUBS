import Foundation

/// Reads a subtitle file someone else made.
///
/// Two quite different files arrive with the same extension. Most `.srt` files hold a
/// sentence or two per cue, which are subtitles already. Some hold a single word per
/// cue, which are not subtitles at all - they are word timings, and they are what the
/// karaoke and spotlight styles need. Those are worth far more to this app, so they are
/// recognised and kept as timings rather than flattened into one-word captions.
enum SRTImporter {

    struct Cue: Equatable {
        let start: TimeInterval
        let end: TimeInterval
        let text: String
    }

    enum Failure: LocalizedError {
        case unreadable
        case empty

        var errorDescription: String? {
            switch self {
            case .unreadable: return String(localized: "Unable to read subtitle file")
            case .empty: return String(localized: "No subtitles in that file")
            }
        }

        var failureReason: String? {
            switch self {
            case .unreadable:
                return String(localized: "The file could not be opened as text. It may not be an .srt file.")
            case .empty:
                return String(localized: "The file opened, but nothing in it looked like a subtitle.")
            }
        }
    }

    // MARK: - Reading

    static func read(contentsOf url: URL) throws -> [SubtitleSegment] {
        // Subtitle files come from everywhere; UTF-8 is the common case but far from
        // the only one, and a failed decode should not look like an empty file.
        let text: String
        if let utf8 = try? String(contentsOf: url, encoding: .utf8) {
            text = utf8
        } else if let guessed = try? String(contentsOf: url, encoding: .isoLatin1) {
            text = guessed
        } else {
            throw Failure.unreadable
        }

        let subtitles = subtitles(from: parse(text))
        guard !subtitles.isEmpty else { throw Failure.empty }
        return subtitles
    }

    // MARK: - Parsing
    /// Pulls the cues out of an SRT file.
    ///
    /// Written line by line rather than block by block, because the layout varies more
    /// than the format suggests. The textbook file puts the number, the timing and the
    /// text on three separate lines; plenty of tools write all three on one. Both are
    /// read here, and so is a file with no blank lines between its cues.
    ///
    /// Anything malformed is skipped rather than failing the whole file for one bad cue.
    static func parse(_ text: String) -> [Cue] {
        let normalised = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\u{FEFF}", with: "")

        var cues: [Cue] = []
        var timing: (start: TimeInterval, end: TimeInterval)?
        var body: [String] = []

        func close() {
            defer { timing = nil; body = [] }
            guard let timing else { return }

            // In files that give each cue its own number line, the *next* cue's number
            // has just been collected as the last line of this one's text.
            if let last = body.last, !last.isEmpty, last.allSatisfy(\.isNumber) {
                body.removeLast()
            }

            let text = body.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return }
            cues.append(Cue(start: timing.start, end: max(timing.end, timing.start), text: text))
        }

        for line in normalised.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            guard let found = splitTiming(trimmed) else {
                if !trimmed.isEmpty { body.append(trimmed) }
                continue
            }

            close()
            timing = (found.start, found.end)
            if !found.text.isEmpty { body.append(found.text) }
        }
        close()

        return cues.sorted { $0.start < $1.start }
    }

    /// Reads a line containing `-->`, wherever the timings sit in it.
    ///
    /// The start stamp is whatever comes last before the arrow, so a cue number in
    /// front of it is simply ignored. The end stamp is whatever comes first after it,
    /// so any text sharing the line is what remains.
    private static func splitTiming(_ line: String) -> (start: TimeInterval, end: TimeInterval, text: String)? {
        guard let arrow = line.range(of: "-->") else { return nil }

        guard let startStamp = line[..<arrow.lowerBound].split(whereSeparator: \.isWhitespace).last,
              let start = seconds(from: String(startStamp))
        else { return nil }

        var after = line[arrow.upperBound...].split(whereSeparator: \.isWhitespace).map(String.init)
        guard !after.isEmpty, let end = seconds(from: after.removeFirst()) else { return nil }

        return (start, end, after.joined(separator: " "))
    }


    /// `HH:MM:SS,mmm`, and the several things people write instead: a full stop for the
    /// comma, no hours, no milliseconds.
    static func seconds(from stamp: String) -> TimeInterval? {
        let cleaned = stamp
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: ",", with: ".")
        guard !cleaned.isEmpty else { return nil }

        let pieces = cleaned.components(separatedBy: ":")
        guard (1...3).contains(pieces.count) else { return nil }

        var total: TimeInterval = 0
        for piece in pieces {
            guard let value = Double(piece), value >= 0 else { return nil }
            total = total * 60 + value
        }
        return total
    }

    // MARK: - Cues into subtitles

    /// Below this many words per cue on average, the file is word timings rather than
    /// captions. Deliberately not "exactly one word": real word-timed files still carry
    /// the odd "New York" or hyphenated pair in a single cue.
    private static let wordTimingThreshold = 1.4

    static func subtitles(from cues: [Cue]) -> [SubtitleSegment] {
        guard !cues.isEmpty else { return [] }

        let averageWords = Double(cues.reduce(0) { $0 + $1.text.split(whereSeparator: \.isWhitespace).count })
            / Double(cues.count)

        guard averageWords <= wordTimingThreshold else {
            // Ordinary subtitles: each cue is already a caption, line breaks and all.
            return cues.map {
                SubtitleSegment(startTime: $0.start, endTime: $0.end, text: $0.text)
            }
        }

        // Word timings: every cue becomes a word, and the words are gathered into
        // subtitles the same way the speech engines' words are.
        let words = cues.map {
            SubtitleWord(
                word: $0.text.replacingOccurrences(of: "\n", with: " "),
                startTime: $0.start,
                endTime: $0.end
            )
        }
        return SubtitleSegmenter.group(words: words)
    }

    /// What language the file looks like, from its script.
    ///
    /// A subtitle file says nothing about its own language, so the letters are the only
    /// evidence there is. Only Greek is distinguished, because that is the only one the
    /// app treats differently.
    static func languageCode(of subtitles: [SubtitleSegment]) -> String {
        let sample = subtitles.prefix(20).map(\.text).joined()
        let isGreek = sample.unicodeScalars.contains { (0x0370...0x03FF).contains($0.value) }
        return isGreek ? "el" : "en"
    }

    /// Whether a file's cues are word timings. Used to tell the user what they just
    /// imported, since the two are worth very different things.
    static func isWordTimed(_ cues: [Cue]) -> Bool {
        guard !cues.isEmpty else { return false }
        let averageWords = Double(cues.reduce(0) { $0 + $1.text.split(whereSeparator: \.isWhitespace).count })
            / Double(cues.count)
        return averageWords <= wordTimingThreshold
    }
}

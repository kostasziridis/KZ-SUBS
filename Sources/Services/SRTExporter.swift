import Foundation

/// Writes subtitles as SubRip (.srt), the format every player and editor understands.
enum SRTExporter {

    /// How much of a subtitle goes in one cue.
    ///
    /// A file of whole subtitles is what a player wants. A file of single words is what
    /// an editor wants for word-by-word captions - the same shape the app can import -
    /// and it is the only form that carries the timings the karaoke and spotlight
    /// styles run on.
    enum Granularity: String, CaseIterable, Identifiable, Sendable {
        case subtitles
        case words

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .subtitles: return String(localized: "Whole subtitles")
            case .words: return String(localized: "One word at a time")
            }
        }

        var detail: String {
            switch self {
            case .subtitles:
                return String(localized: "What a player or editor expects.")
            case .words:
                return String(localized: "Every word with its own timing, for word-by-word captions elsewhere.")
            }
        }
    }

    /// Builds the SRT text.
    ///
    /// Line breaks inside a subtitle are kept: they are the two-line layout the user
    /// sees, and SubRip carries them as real newlines.
    static func makeSRT(from segments: [SubtitleSegment], granularity: Granularity = .subtitles) -> String {
        cues(from: segments, granularity: granularity)
            .enumerated()
            .map { index, cue in
                """
                \(index + 1)
                \(TimecodeFormatter.srt(cue.start)) --> \(TimecodeFormatter.srt(cue.end))
                \(cue.text)
                """
            }
            .joined(separator: "\n\n")
            + "\n"
    }

    private struct Cue {
        let start: TimeInterval
        let end: TimeInterval
        let text: String
    }

    private static func cues(from segments: [SubtitleSegment], granularity: Granularity) -> [Cue] {
        let ordered = segments.sorted { $0.startTime < $1.startTime }

        guard granularity == .words else {
            return ordered.map { Cue(start: $0.startTime, end: $0.endTime, text: $0.text) }
        }

        return ordered.flatMap { segment -> [Cue] in
            // A subtitle written by hand has no word timings. Splitting its text and
            // inventing them would be a worse answer than one honest cue.
            guard let words = segment.words, !words.isEmpty else {
                return [Cue(start: segment.startTime, end: segment.endTime, text: segment.text)]
            }
            return words.map { Cue(start: $0.startTime, end: $0.endTime, text: $0.word) }
        }
    }

    /// Writes the file and returns it, ready to share.
    ///
    /// Encoded UTF-8 without a byte order mark, which is what players expect and what
    /// keeps Greek readable everywhere.
    static func write(
        _ segments: [SubtitleSegment],
        name: String,
        granularity: Granularity = .subtitles
    ) throws -> URL {
        guard !segments.isEmpty else { throw AppError.exportFailed }

        StorageManager.ensureDirectoryExists(StorageManager.workingDirectory)
        // Named apart, so both kinds can be made from one project and told apart in a
        // share sheet afterwards.
        let suffix = granularity == .words ? "-words" : ""
        let url = StorageManager.uniqueURL(
            in: StorageManager.workingDirectory,
            preferredName: "\(safeName(name))\(suffix).srt",
            fallbackExtension: "srt"
        )

        let text = makeSRT(from: segments, granularity: granularity)
        guard let data = text.data(using: .utf8) else { throw AppError.exportFailed }

        try data.write(to: url, options: .atomic)
        return url
    }

    /// Keeps the filename usable on any system the file might be opened on.
    private static func safeName(_ name: String) -> String {
        let cleaned = name
            .components(separatedBy: CharacterSet(charactersIn: "/\\:*?\"<>|"))
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Subtitles" : cleaned
    }
}

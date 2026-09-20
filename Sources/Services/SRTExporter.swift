import Foundation

/// Writes subtitles as SubRip (.srt), the format every player and editor understands.
enum SRTExporter {

    /// Builds the SRT text.
    ///
    /// Line breaks inside a subtitle are kept: they are the two-line layout the user
    /// sees, and SubRip carries them as real newlines.
    static func makeSRT(from segments: [SubtitleSegment]) -> String {
        segments
            .sorted { $0.startTime < $1.startTime }
            .enumerated()
            .map { index, segment in
                """
                \(index + 1)
                \(TimecodeFormatter.srt(segment.startTime)) --> \(TimecodeFormatter.srt(segment.endTime))
                \(segment.text)
                """
            }
            .joined(separator: "\n\n")
            + "\n"
    }

    /// Writes the file and returns it, ready to share.
    ///
    /// Encoded UTF-8 without a byte order mark, which is what players expect and what
    /// keeps Greek readable everywhere.
    static func write(_ segments: [SubtitleSegment], name: String) throws -> URL {
        guard !segments.isEmpty else { throw AppError.exportFailed }

        StorageManager.ensureDirectoryExists(StorageManager.workingDirectory)
        let url = StorageManager.uniqueURL(
            in: StorageManager.workingDirectory,
            preferredName: "\(safeName(name)).srt",
            fallbackExtension: "srt"
        )

        let text = makeSRT(from: segments)
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

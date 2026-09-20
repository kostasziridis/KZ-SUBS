import Foundation

/// A single spoken word with its own timing.
///
/// Word timings are kept even when the UI does not use them yet: they are what makes
/// karaoke-style highlighting possible later without re-transcribing anything.
struct SubtitleWord: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    var word: String
    let startTime: TimeInterval
    let endTime: TimeInterval
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

    var duration: TimeInterval { max(0, endTime - startTime) }

    func contains(_ time: TimeInterval) -> Bool {
        time >= startTime && time < endTime
    }

    /// The word being spoken at `time`, when word timings are available.
    func word(at time: TimeInterval) -> SubtitleWord? {
        words?.first { time >= $0.startTime && time < $0.endTime }
    }
}

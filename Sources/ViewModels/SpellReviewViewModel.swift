import Foundation
import Observation

/// One word the dictionary does not have, and where it is.
struct SpellFinding: Identifiable, Equatable {
    let id: UUID
    let segmentID: SubtitleSegment.ID
    /// The subtitle's place in the list, so the review can say "subtitle 7".
    let segmentNumber: Int
    let word: String
    /// Which word to rename. Nil when the subtitle has no word timings, in which case
    /// the text has to be edited instead.
    let wordID: SubtitleWord.ID?
    /// The whole subtitle, so the word can be read in context before changing it.
    let context: String
    var suggestions: [String] = []

    /// When the playhead should move to see it.
    let startTime: TimeInterval
}

/// Checks every subtitle at once, rather than one at a time in the editor.
///
/// Editing a subtitle shows its own suspect words, which is the right place to fix one
/// you are already looking at. It is the wrong place to answer "is this whole video
/// spelled correctly" - for that nothing must be left to whether the user happened to
/// open every subtitle.
@MainActor
@Observable
final class SpellReviewViewModel {

    private(set) var findings: [SpellFinding] = []
    private(set) var isChecking = false
    /// Set once a pass has finished, so "nothing found" can be told apart from
    /// "nothing checked yet".
    private(set) var hasChecked = false

    @ObservationIgnored private var scan: Task<Void, Never>?

    var count: Int { findings.count }

    // MARK: - Checking

    /// Looks over every subtitle. Suggestions are fetched for each finding as it is
    /// found, because a review with no suggestions is just a list of complaints.
    func check(_ segments: [SubtitleSegment]) {
        scan?.cancel()
        isChecking = true

        scan = Task { [weak self] in
            var found: [SpellFinding] = []

            for (index, segment) in segments.enumerated() {
                if Task.isCancelled { return }

                let words = segment.words ?? SpellReviewViewModel.words(in: segment.text)
                let unknown = await SpellCheck.unknownWords(in: words.map(\.word))
                guard !unknown.isEmpty else { continue }

                for word in words where unknown.contains(word.word) {
                    // A name the user has already kept is not a mistake any more.
                    guard !LearnedWords.shared.knows(word.word) else { continue }

                    found.append(
                        SpellFinding(
                            id: word.id,
                            segmentID: segment.id,
                            segmentNumber: index + 1,
                            word: word.word,
                            wordID: segment.words == nil ? nil : word.id,
                            context: segment.text,
                            suggestions: await SpellCheck.suggestions(for: word.word),
                            startTime: segment.startTime
                        )
                    )
                }
            }

            guard let self, !Task.isCancelled else { return }
            self.findings = found
            self.isChecking = false
            self.hasChecked = true
        }
    }

    func cancel() {
        scan?.cancel()
        scan = nil
        isChecking = false
    }

    // MARK: - Acting on a finding

    /// Forgets a finding once it has been dealt with, so the list only holds what is
    /// still outstanding.
    func remove(_ finding: SpellFinding) {
        findings.removeAll { $0.id == finding.id }
    }

    /// Accepts the word as it is, everywhere, now and later.
    func keep(_ finding: SpellFinding) {
        LearnedWords.shared.learn(finding.word)
        // Every other finding for the same word goes too: being asked twice about one
        // name is exactly what "keep" is meant to prevent.
        let folded = GreekSpellChecker.fold(finding.word)
        findings.removeAll { GreekSpellChecker.fold($0.word) == folded }
    }

    // MARK: - Words without timings

    /// Splits a subtitle that has no word timings into stand-in words.
    ///
    /// Hand-written subtitles have no timings, and they still deserve checking. The ids
    /// are made up here, which is why a finding from one is applied to the text rather
    /// than to a word.
    static func words(in text: String) -> [SubtitleWord] {
        text.split(whereSeparator: \.isWhitespace).map {
            SubtitleWord(word: String($0), startTime: 0, endTime: 0)
        }
    }
}

import Foundation
import Observation

/// Words the user has said are fine.
///
/// A dictionary cannot know a surname, a village or a brand, and a spelling review
/// that keeps asking about the same name is a review nobody finishes. Saying "keep"
/// once should be the end of it, for this video and every one after.
@MainActor
@Observable
final class LearnedWords {

    static let shared = LearnedWords()

    private static let key = "learnedWords"

    /// Stored folded - accents and case are exactly what varies between one telling of
    /// a name and the next, and neither changes whether the word is a word.
    private var folded: Set<String>

    private init() {
        folded = Set(UserDefaults.standard.stringArray(forKey: Self.key) ?? [])
    }

    var count: Int { folded.count }

    func knows(_ word: String) -> Bool {
        folded.contains(GreekSpellChecker.fold(word))
    }

    func learn(_ word: String) {
        let key = GreekSpellChecker.fold(word)
        guard !key.isEmpty else { return }
        folded.insert(key)
        UserDefaults.standard.set(Array(folded), forKey: Self.key)
    }

    func forgetEverything() {
        folded.removeAll()
        UserDefaults.standard.removeObject(forKey: Self.key)
    }
}

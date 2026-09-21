import Foundation
import UIKit

/// Spelling help for the subtitle editor, from whichever checker knows the language.
///
/// iOS has one built in and it is good, but it has no Greek dictionary behind it - it
/// does not flag even nonsense in Greek, while it flags French, German, Spanish,
/// Italian and Russian correctly. So Greek words go to `GreekSpellChecker`, which
/// carries its own dictionary, and everything else to the system.
///
/// Decided per word rather than per project, because a Greek video says "DJI" and
/// "Mavic" too.
enum SpellCheck {

    /// Which of the words given are not words at all.
    static func unknownWords(in words: [String]) async -> Set<String> {
        let greek = words.filter(isGreek)
        let rest = words.filter { !isGreek($0) }

        var unknown = await GreekSpellChecker.shared.unknownWords(in: greek)
        unknown.formUnion(await systemUnknownWords(in: rest))
        return unknown
    }

    /// What the word was probably meant to be, best first.
    static func suggestions(for word: String, limit: Int = 4) async -> [String] {
        if isGreek(word) {
            return await GreekSpellChecker.shared.suggestions(for: word, limit: limit)
        }
        return await systemSuggestions(for: word, limit: limit)
    }

    /// Loads the Greek dictionary so the first word checked does not wait for it.
    static func prepare() {
        Task.detached(priority: .utility) {
            _ = await GreekSpellChecker.shared.unknownWords(in: ["καλημέρα"])
        }
    }

    // MARK: - The system checker

    /// `UITextChecker` is UIKit and not safe to share across threads, so it is used on
    /// the main actor and nowhere else.
    @MainActor
    private static func systemUnknownWords(in words: [String]) -> Set<String> {
        guard !words.isEmpty, let language = systemLanguage() else { return [] }

        let checker = UITextChecker()
        var unknown: Set<String> = []

        for word in words {
            let trimmed = word.trimmingCharacters(in: CharacterSet.punctuationCharacters.union(.whitespaces))
            // Numbers, timecodes and stray punctuation are not misspellings.
            guard trimmed.count > 1, trimmed.contains(where: \.isLetter) else { continue }

            let range = NSRange(location: 0, length: (trimmed as NSString).length)
            let misspelled = checker.rangeOfMisspelledWord(
                in: trimmed, range: range, startingAt: 0, wrap: false, language: language
            )
            if misspelled.location != NSNotFound { unknown.insert(word) }
        }
        return unknown
    }

    @MainActor
    private static func systemSuggestions(for word: String, limit: Int) -> [String] {
        guard let language = systemLanguage() else { return [] }

        let trimmed = word.trimmingCharacters(in: CharacterSet.punctuationCharacters.union(.whitespaces))
        let range = NSRange(location: 0, length: (trimmed as NSString).length)
        let guesses = UITextChecker().guesses(forWordRange: range, in: trimmed, language: language) ?? []
        return Array(guesses.prefix(limit))
    }

    /// The first of the user's languages the system can actually spell-check.
    @MainActor
    private static func systemLanguage() -> String? {
        let available = Set(UITextChecker.availableLanguages)
        for preferred in Locale.preferredLanguages {
            if available.contains(preferred) { return preferred }
            if let match = available.first(where: { $0.hasPrefix(preferred.prefix(2)) }) { return match }
        }
        return available.contains("en_US") ? "en_US" : available.first
    }

    // MARK: - Script

    private static func isGreek(_ word: String) -> Bool {
        word.unicodeScalars.contains { (0x0370...0x03FF).contains($0.value) || (0x1F00...0x1FFF).contains($0.value) }
    }
}

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
///
/// Whether the system has a Greek dictionary is asked rather than assumed, because
/// `availableLanguages` says it does and the behaviour says otherwise. Where it turns
/// out to work, its suggestions are offered alongside ours; what counts as a mistake
/// is still decided by our dictionary alone, so the same word is never a mistake on
/// one phone and fine on another.
enum SpellCheck {

    /// Which of the words given are not words at all.
    static func unknownWords(in words: [String]) async -> Set<String> {
        let greek = words.filter(isGreek)
        let rest = words.filter { !isGreek($0) }

        var unknown = await GreekSpellChecker.shared.unknownWords(in: greek)
        unknown.formUnion(await systemUnknownWords(in: rest))

        // A word the user has kept is a word, whatever any dictionary says.
        let learned = await LearnedWords.shared
        for word in unknown where await learned.knows(word) {
            unknown.remove(word)
        }
        return unknown
    }

    /// What the word was probably meant to be, best first.
    static func suggestions(for word: String, limit: Int = 4) async -> [String] {
        guard isGreek(word) else {
            return await systemSuggestions(for: word, limit: limit)
        }

        var found = await GreekSpellChecker.shared.suggestions(for: word, limit: limit)

        // Only worth asking where there is something behind the language, and only to
        // add what ours did not think of.
        if await systemKnowsGreek() {
            for extra in await systemSuggestions(for: word, limit: limit, language: "el_GR")
            where !found.contains(extra) {
                found.append(extra)
            }
        }

        return Array(found.prefix(limit))
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
    private static func systemSuggestions(for word: String, limit: Int, language: String? = nil) -> [String] {
        guard let language = language ?? systemLanguage() else { return [] }

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

    /// Puts a suggestion back into the shape of the word it replaces.
    ///
    /// A dictionary holds bare lowercase words, but a caption holds «Ολα» at the start
    /// of a sentence and «ιντερνετ.» at the end of one. Dropping straight in would take
    /// the capital off the first and the full stop off the second - a correction that
    /// introduces two new mistakes.
    static func shaped(_ suggestion: String, like original: String) -> String {
        let punctuation = CharacterSet.punctuationCharacters

        let leading = String(original.prefix { $0.unicodeScalars.allSatisfy(punctuation.contains) })
        let trailing = String(original.reversed().prefix { $0.unicodeScalars.allSatisfy(punctuation.contains) }.reversed())
        let core = original.dropFirst(leading.count).dropLast(trailing.count)

        var replacement = suggestion
        // Only the first letter: an all-capitals caption is the style's doing, applied
        // when it is drawn, and must not be written into the words themselves.
        if let first = core.first, first.isUppercase,
           let replacementFirst = replacement.first, replacementFirst.isLowercase {
            replacement = replacementFirst.uppercased() + replacement.dropFirst()
        }

        return leading + replacement + trailing
    }

    // MARK: - What the system can actually do

    /// Whether the system's checker has a Greek dictionary behind it.
    ///
    /// `availableLanguages` lists `el_GR` on every iOS this has been tried on, and on
    /// none of them does it flag so much as pure nonsense - while French, German,
    /// Spanish, Italian and Russian all flag theirs. So the only trustworthy answer
    /// comes from handing it a word that is certainly not one and seeing whether it
    /// notices. Asked once.
    @MainActor
    private static func systemKnowsGreek() -> Bool {
        if let known = greekSupport { return known }

        let nonsense = "ξκλψδφγη"
        let range = NSRange(location: 0, length: (nonsense as NSString).length)
        let found = UITextChecker().rangeOfMisspelledWord(
            in: nonsense, range: range, startingAt: 0, wrap: false, language: "el_GR"
        )

        let known = found.location != NSNotFound
        greekSupport = known
        AppLog.app.notice("System Greek spell checking: \(known ? "available" : "absent", privacy: .public)")
        return known
    }

    @MainActor
    private static var greekSupport: Bool?

    // MARK: - Script

    private static func isGreek(_ word: String) -> Bool {
        word.unicodeScalars.contains { (0x0370...0x03FF).contains($0.value) || (0x1F00...0x1FFF).contains($0.value) }
    }
}

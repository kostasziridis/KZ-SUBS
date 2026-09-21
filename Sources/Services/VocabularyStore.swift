import Foundation
import Observation

/// Words the user wants written the way they write them.
///
/// Speech recognition guesses at names it has never heard: a brand, a village, a
/// colleague. Correcting those afterwards is work that repeats with every video, so
/// they are collected here once and handed to the engine before it starts listening.
///
/// Kept small on purpose. The engine only accepts a short piece of context, and a long
/// list would push the words that matter out of it.
@MainActor
@Observable
final class VocabularyStore {

    static let shared = VocabularyStore()

    /// Beyond this the engine cannot hold them all anyway, and the list stops being
    /// something anyone maintains.
    static let maximumTerms = 30

    private static let key = "customVocabulary"

    private(set) var terms: [String]

    private init() {
        terms = UserDefaults.standard.stringArray(forKey: Self.key) ?? []
    }

    var isFull: Bool { terms.count >= Self.maximumTerms }

    /// Adds a word, unless it is blank, already there, or the list is full.
    @discardableResult
    func add(_ term: String) -> Bool {
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isFull else { return false }
        guard !terms.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) else { return false }

        terms.append(trimmed)
        save()
        return true
    }

    func remove(atOffsets offsets: IndexSet) {
        terms.remove(atOffsets: offsets)
        save()
    }

    func move(fromOffsets offsets: IndexSet, toOffset destination: Int) {
        // Order is not decoration: the engine takes what fits from the top, so moving a
        // word up is how the user says it matters more.
        terms.move(fromOffsets: offsets, toOffset: destination)
        save()
    }

    private func save() {
        UserDefaults.standard.set(terms, forKey: Self.key)
    }
}

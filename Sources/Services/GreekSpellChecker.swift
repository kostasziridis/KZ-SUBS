import Foundation

/// Finds Greek words that are not words, and offers the ones they were meant to be.
///
/// iOS has a spell checker with Greek in its list of languages, but no Greek
/// dictionary behind it - it does not flag even pure nonsense, while French, German,
/// Spanish, Italian and Russian all work. Apple's on-device language model does not
/// know Greek either. So the dictionary ships with the app: `Tools/build-greek-
/// dictionary.py` turns the el_GR Hunspell word list into `GreekWords.bin`, and this
/// searches it.
///
/// An actor because the payload is unpacked once and shared, and because a lookup has
/// no business on the main thread.
actor GreekSpellChecker {

    static let shared = GreekSpellChecker()

    /// Letters a Greek word can be misspelled with, accents already folded away.
    private static let alphabet = Array("αβγδεζηθικλμνξοπρστυφχψω")

    private var index: Index?
    private var loadFailed = false

    private init() {}

    // MARK: - Public

    /// The words here that the dictionary does not have, lowercased comparison.
    ///
    /// Anything that is not Greek letters is passed over rather than reported: a
    /// number, a Latin brand name or a bare piece of punctuation is not this
    /// dictionary's business and flagging it would only cry wolf.
    func unknownWords(in words: [String]) -> Set<String> {
        guard let index = loadedIndex() else { return [] }

        var unknown: Set<String> = []
        for word in words {
            let trimmed = Self.trimmed(word)
            guard Self.isGreek(trimmed) else { continue }
            if !index.contains(trimmed) { unknown.insert(word) }
        }
        return unknown
    }

    /// What the word was probably meant to be, best first.
    ///
    /// An accent in the wrong place is by far the commonest mistake and is answered by
    /// a single lookup, because the dictionary is ordered by the accent-free form.
    /// Only when that finds nothing is one letter's worth of alternatives tried.
    func suggestions(for word: String, limit: Int = 4) -> [String] {
        guard let index = loadedIndex() else { return [] }

        let trimmed = Self.trimmed(word)
        guard Self.isGreek(trimmed) else { return [] }

        let key = Self.fold(trimmed)
        let sameLetters = index.forms(folded: key).filter { $0.caseInsensitiveCompare(trimmed) != .orderedSame }
        if !sameLetters.isEmpty {
            return Array(sameLetters.prefix(limit))
        }

        var found: [String] = []
        var seen: Set<String> = []
        // Sorted so the dictionary is walked forwards, which keeps each lookup near
        // the last one rather than jumping about.
        for candidate in Self.oneLetterOut(key).sorted() {
            for form in index.forms(folded: candidate) where !seen.contains(form) {
                seen.insert(form)
                found.append(form)
            }
        }

        // Shortest first: a word one letter out is a likelier fix than one two apart
        // that happens to share a stem.
        return Array(found.sorted { $0.count < $1.count }.prefix(limit))
    }

    // MARK: - Text

    /// The same folding `build-greek-dictionary.py` applies. The two must agree
    /// exactly or every lookup misses.
    static func fold(_ word: String) -> String {
        var result = ""
        result.reserveCapacity(word.count)
        for scalar in word.lowercased().decomposedStringWithCanonicalMapping.unicodeScalars {
            guard scalar.properties.generalCategory != .nonspacingMark else { continue }
            result.unicodeScalars.append(scalar == "ς" ? "σ" : scalar)
        }
        return result
    }

    /// Strips what a caption puts around a word but a dictionary never contains.
    private static func trimmed(_ word: String) -> String {
        word.trimmingCharacters(in: CharacterSet.punctuationCharacters.union(.whitespaces))
    }

    private static func isGreek(_ word: String) -> Bool {
        guard !word.isEmpty else { return false }
        return word.unicodeScalars.allSatisfy { scalar in
            (0x0370...0x03FF).contains(scalar.value) || (0x1F00...0x1FFF).contains(scalar.value)
        }
    }

    /// Every word one insertion, deletion, substitution or swap away.
    private static func oneLetterOut(_ word: String) -> Set<String> {
        var result: Set<String> = []
        let letters = Array(word)

        for position in 0...letters.count {
            if position < letters.count {
                var deleted = letters
                deleted.remove(at: position)
                result.insert(String(deleted))

                for letter in alphabet where letter != letters[position] {
                    var swapped = letters
                    swapped[position] = letter
                    result.insert(String(swapped))
                }
            }
            for letter in alphabet {
                var inserted = letters
                inserted.insert(letter, at: position)
                result.insert(String(inserted))
            }
        }

        for position in 0..<max(0, letters.count - 1) {
            var transposed = letters
            transposed.swapAt(position, position + 1)
            result.insert(String(transposed))
        }

        result.remove(word)
        return result
    }

    // MARK: - Loading

    private func loadedIndex() -> Index? {
        if let index { return index }
        guard !loadFailed else { return nil }

        guard let url = Bundle.main.url(forResource: "GreekWords", withExtension: "bin"),
              let loaded = Index(contentsOf: url) else {
            // Nothing to be done at runtime, and nothing worth interrupting the user
            // for: the words simply go unchecked.
            AppLog.storage.error("Greek dictionary missing or unreadable")
            loadFailed = true
            return nil
        }

        index = loaded
        return loaded
    }
}

// MARK: - The file

/// The packed word list: a header, a block index, and one deflated payload.
///
/// Words are ordered by their accent-free form, so every spelling of the same letters
/// sits together and one search finds them all. Within a block each word is stored as
/// the number of leading bytes it shares with the one before it plus the rest, which
/// is what keeps 828,806 words down to a megabyte and a half.
private struct Index {

    private let payload: [UInt8]
    private let blockStarts: [Int]
    private let blockSize: Int

    init?(contentsOf url: URL) {
        guard let file = try? Data(contentsOf: url, options: .mappedIfSafe), file.count > 18 else { return nil }
        let bytes = [UInt8](file)

        guard bytes[0] == 0x4B, bytes[1] == 0x5A, bytes[2] == 0x47, bytes[3] == 0x57 else { return nil }  // "KZGW"
        guard bytes[4] == 1 else { return nil }

        func uint32(at offset: Int) -> Int {
            Int(bytes[offset])
                | Int(bytes[offset + 1]) << 8
                | Int(bytes[offset + 2]) << 16
                | Int(bytes[offset + 3]) << 24
        }

        blockSize = Int(bytes[5])
        let blockCount = uint32(at: 10)
        let payloadLength = uint32(at: 14)

        let indexStart = 18
        let indexEnd = indexStart + blockCount * 4
        guard bytes.count > indexEnd, blockSize > 0 else { return nil }

        blockStarts = (0..<blockCount).map { uint32(at: indexStart + $0 * 4) }

        let compressed = file.subdata(in: indexEnd..<file.count)
        guard let unpacked = try? (compressed as NSData).decompressed(using: .zlib),
              unpacked.count == payloadLength else { return nil }
        payload = [UInt8](unpacked)
    }

    func contains(_ word: String) -> Bool {
        forms(folded: GreekSpellChecker.fold(word)).contains { $0.caseInsensitiveCompare(word) == .orderedSame }
    }

    /// Every spelling stored under this accent-free key.
    func forms(folded key: String) -> [String] {
        guard !key.isEmpty else { return [] }
        let target = Array(key.utf8)

        var block = block(notAfter: target)
        var result: [String] = []

        // A group can run over the end of a block, so keep going while the words still
        // fold to the key.
        while block < blockStarts.count {
            var passedIt = false
            for word in words(inBlock: block) {
                let folded = Array(GreekSpellChecker.fold(word).utf8)
                if folded == target {
                    result.append(word)
                } else if !result.isEmpty || Self.isOrderedAfter(folded, target) {
                    passedIt = true
                    break
                }
            }
            if passedIt { break }
            block += 1
        }

        return result
    }

    // MARK: - Searching

    /// The last block whose first word is not past `target`.
    private func block(notAfter target: [UInt8]) -> Int {
        var low = 0
        var high = blockStarts.count - 1

        while low < high {
            let middle = (low + high + 1) / 2
            guard let first = words(inBlock: middle).first else { break }
            if Self.isOrderedAfter(Array(GreekSpellChecker.fold(first).utf8), target) {
                high = middle - 1
            } else {
                low = middle
            }
        }
        return low
    }

    /// UTF-8 bytes compare in the same order as the characters they spell, which is the
    /// order the file was written in.
    private static func isOrderedAfter(_ lhs: [UInt8], _ rhs: [UInt8]) -> Bool {
        for (left, right) in zip(lhs, rhs) where left != right {
            return left > right
        }
        return lhs.count > rhs.count
    }

    // MARK: - Decoding

    private func words(inBlock block: Int) -> [String] {
        guard block >= 0, block < blockStarts.count else { return [] }

        let start = blockStarts[block]
        let end = block + 1 < blockStarts.count ? blockStarts[block + 1] : payload.count
        guard start < end, end <= payload.count else { return [] }

        var words: [String] = []
        words.reserveCapacity(blockSize)

        var previous: [UInt8] = []
        var cursor = start

        while cursor < end {
            let shared = Int(payload[cursor])
            cursor += 1
            guard shared <= previous.count else { return words }

            var bytes = Array(previous.prefix(shared))
            while cursor < end, payload[cursor] != 0x0A {
                bytes.append(payload[cursor])
                cursor += 1
            }
            cursor += 1  // the newline

            previous = bytes
            if let word = String(bytes: bytes, encoding: .utf8) { words.append(word) }
        }

        return words
    }
}

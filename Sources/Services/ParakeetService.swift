import FluidAudio
import Foundation

/// The second engine: NVIDIA's Parakeet, running on the Neural Engine through Core ML.
///
/// Here to be compared with Whisper rather than to replace it. It is a third the size,
/// speaks the same 25 European languages including Greek, and returns timings per
/// token rather than per word - which is finer than we need, and has to be assembled
/// back into words before the app can use it.
///
/// The only place in the app that knows this package exists, exactly as `WhisperService`
/// is the only place that knows about WhisperKit.
actor ParakeetService {

    static let shared = ParakeetService()

    /// What the engine puts where a word begins.
    ///
    /// The model works in SentencePiece pieces, whose marker is U+2581, but the package
    /// has already turned that into an ordinary leading space by the time we see it -
    /// tokens arrive as " Κ", "α", "λη", "μέ", "ρα", " σε". Both are accepted, because
    /// which one arrives is the package's business and not ours.
    private static let wordStarts: Set<Character> = [" ", "\u{2581}"]

    /// What the engine writes when it cannot make a character out. Greek final sigma
    /// trips it, so this is not rare; better an incomplete word than `<unk>` in a
    /// caption.
    private static let unknownToken = "<unk>"

    private var manager: AsrManager?

    private init() {}

    // MARK: - Preparation

    func prepare(onProgress: @escaping @Sendable (ModelPreparation) -> Void) async throws {
        onProgress(.checking)

        if manager != nil {
            onProgress(.ready)
            return
        }

        StorageManager.ensureDirectoryExists(StorageManager.modelsDirectory)
        let directory = StorageManager.modelsDirectory.appendingPathComponent("parakeet", isDirectory: true)

        // Say "downloading" only when something is actually being fetched. Loading a
        // model already on the device is a different wait and deserves a different word.
        let alreadyHere = AsrModels.modelsExist(at: directory)
        onProgress(alreadyHere ? .loading : .downloading(0))

        do {
            let models = try await AsrModels.downloadAndLoad(
                to: directory,
                version: .v3,
                progressHandler: { progress in
                    guard !alreadyHere else { return }
                    onProgress(.downloading(progress.fractionCompleted))
                }
            )

            onProgress(.loading)
            let manager = AsrManager(config: .default)
            try await manager.loadModels(models)
            self.manager = manager
            onProgress(.ready)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            AppLog.speech.error("Parakeet preparation failed: \(error.localizedDescription, privacy: .public)")
            throw AppError.unableToPrepareModel
        }
    }

    // MARK: - Transcription

    func transcribe(
        audioURL: URL,
        language: AppLanguage,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws -> SpeechTranscript {
        guard let manager else { throw AppError.unableToPrepareModel }

        try Task.checkCancellation()
        let started = Date()

        // Progress arrives on its own stream rather than through a callback, and only
        // for audio long enough to be split, so short clips simply jump to the end.
        let progress = Task {
            for try await fraction in await manager.transcriptionProgressStream {
                onProgress(min(max(fraction, 0), 1))
            }
        }
        defer { progress.cancel() }

        let result: ASRResult
        do {
            var state = try TdtDecoderState(decoderLayers: await manager.decoderLayerCount)
            result = try await manager.transcribe(audioURL, decoderState: &state)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            AppLog.speech.error("Parakeet transcription failed: \(error.localizedDescription, privacy: .public)")
            throw AppError.unableToGenerateSubtitles
        }

        try Task.checkCancellation()
        onProgress(1)

        let timings = result.tokenTimings ?? []
        #if DEBUG
        AppLog.speech.debug(
            "Parakeet tokens (\(timings.count, privacy: .public)): \(timings.prefix(40).map(\.token).joined(separator: "|"), privacy: .public)"
        )
        #endif

        let words = Self.words(from: timings)
        let segments = Self.segments(from: words, fallbackText: Self.readable(result.text), duration: result.duration)

        return SpeechTranscript(
            text: Self.readable(result.text),
            detectedLanguageCode: Self.languageCode(of: result.text, asked: language),
            segments: segments,
            processingTime: Date().timeIntervalSince(started),
            timings: nil
        )
    }

    // MARK: - Tokens into words

    /// Joins the engine's tokens back into words.
    ///
    /// Parakeet writes word pieces, marking the *start* of a word with U+2581 rather
    /// than separating words with spaces. So a word runs from a marked token up to the
    /// next one, and its timing is the first piece's start to the last piece's end.
    static func words(from timings: [TokenTiming]) -> [SubtitleWord] {
        var words: [SubtitleWord] = []
        var letters = ""
        var start: TimeInterval = 0
        var end: TimeInterval = 0

        func flush() {
            let word = letters.trimmingCharacters(in: .whitespaces)
            guard !word.isEmpty else { return }
            words.append(SubtitleWord(word: word, startTime: start, endTime: max(end, start + 0.04)))
        }

        for timing in timings {
            let piece = timing.token
            let beginsWord = piece.first.map(wordStarts.contains) ?? false
            let text = piece
                .replacingOccurrences(of: unknownToken, with: "")
                .filter { $0 != "\u{2581}" }
                .trimmingCharacters(in: .whitespaces)

            if beginsWord {
                flush()
                letters = ""
            }
            if letters.isEmpty { start = timing.startTime }

            letters += text
            end = timing.endTime
        }
        flush()

        return words
    }

    /// Gathers words into the blocks `SubtitleSegmenter` will then reshape.
    ///
    /// Whisper hands back its own decoding windows to start from; Parakeet hands back
    /// one long stream, so the first break has to be found here. A pause is the honest
    /// place to make it, and the end of a sentence a better one.
    static func segments(
        from words: [SubtitleWord],
        fallbackText: String,
        duration: TimeInterval
    ) -> [SubtitleSegment] {
        guard !words.isEmpty else {
            // No timings at all: one block covering the clip is still better than
            // throwing the words away, and the editor can be used to fix it.
            let text = fallbackText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return [] }
            return [SubtitleSegment(startTime: 0, endTime: max(duration, 1), text: text)]
        }

        /// Long enough to be a breath rather than the ordinary gap between words.
        let pause: TimeInterval = 0.6

        var segments: [SubtitleSegment] = []
        var current: [SubtitleWord] = []

        func flush() {
            guard let first = current.first, let last = current.last else { return }
            segments.append(
                SubtitleSegment(
                    startTime: first.startTime,
                    endTime: last.endTime,
                    text: current.map(\.word).joined(separator: " "),
                    words: current
                )
            )
            current = []
        }

        for word in words {
            if let previous = current.last {
                if word.startTime - previous.endTime >= pause || endsSentence(previous.word) {
                    flush()
                }
            }
            current.append(word)
        }
        flush()

        return segments
    }

    private static func endsSentence(_ word: String) -> Bool {
        guard let last = word.trimmingCharacters(in: .whitespaces).last else { return false }
        // Greek uses ";" as its question mark and "·" as a semicolon.
        return ".!?;·…".contains(last)
    }

    /// The engine's own text, with the marks it makes for characters it could not
    /// place taken out. They are not words and must never reach a caption.
    static func readable(_ text: String) -> String {
        text.replacingOccurrences(of: unknownToken, with: "")
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// What language this looks like.
    ///
    /// The engine detects the language but does not say which it picked, so when the
    /// user has not told us either, the script is the only evidence there is.
    static func languageCode(of text: String, asked: AppLanguage) -> String {
        if let code = asked.languageCode { return code }
        let isGreek = text.unicodeScalars.contains { (0x0370...0x03FF).contains($0.value) }
        return isGreek ? "el" : "en"
    }
}

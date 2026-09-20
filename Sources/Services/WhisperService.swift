import AVFoundation
import Foundation
import WhisperKit

/// The only place in the app that talks to WhisperKit.
///
/// An actor because the loaded model is expensive mutable state: two screens must never
/// load or unload it at once. Deliberately not `@MainActor` — all of this is heavy work.
actor WhisperService {

    static let shared = WhisperService()

    private var whisperKit: WhisperKit?
    private var loadedVariant: String?

    private init() {}

    var isReady: Bool { whisperKit != nil }
    var currentVariant: String? { loadedVariant }

    // MARK: - Preparation

    /// Downloads the model if needed and loads it. Safe to call repeatedly: once a model
    /// is loaded this returns immediately.
    func prepare(onProgress: @escaping @Sendable (ModelPreparation) -> Void) async throws {
        if whisperKit != nil {
            onProgress(.ready)
            return
        }

        onProgress(.checking)
        let variant = await ModelManager.resolveVariant()
        AppLog.speech.info("Preparing speech model \(variant, privacy: .public)")

        let folder = try await ModelManager.ensureAvailable(variant: variant) { fraction in
            onProgress(.downloading(fraction))
        }

        try Task.checkCancellation()
        onProgress(.loading)

        do {
            let config = WhisperKitConfig(
                model: variant,
                downloadBase: StorageManager.modelsDirectory,
                modelFolder: folder.path,
                verbose: false,
                logLevel: .error,
                prewarm: false,
                load: true,
                download: false
            )
            let kit = try await WhisperKit(config)
            whisperKit = kit
            loadedVariant = variant
            onProgress(.ready)
        } catch {
            AppLog.speech.error("Model load failed: \(error.localizedDescription, privacy: .public)")
            throw AppError.unableToPrepareModel
        }
    }

    // MARK: - Transcription

    /// Transcribes a local audio file.
    ///
    /// - Parameters:
    ///   - audioURL: a local audio file the engine can read.
    ///   - language: `nil` language code means let the engine detect it.
    ///   - onProgress: coarse 0...1 progress, driven by how far through the audio the
    ///     engine has moved.
    /// - Throws: `CancellationError` if the surrounding task is cancelled.
    func transcribe(
        audioURL: URL,
        language: AppLanguage,
        wordTimestamps: Bool = true,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws -> SpeechTranscript {
        guard let whisperKit else { throw AppError.unableToPrepareModel }

        try Task.checkCancellation()
        let started = Date()

        let options = DecodingOptions(
            verbose: false,
            task: .transcribe,
            language: language.languageCode,
            // Only spend time detecting when the user did not tell us.
            detectLanguage: language.languageCode == nil,
            skipSpecialTokens: true,
            wordTimestamps: wordTimestamps,
            chunkingStrategy: .vad
        )

        // Whisper reads audio in 30-second windows; the window index is the honest
        // measure of how far along it is.
        let totalWindows = max(1.0, (audioDuration(of: audioURL) / 30.0).rounded(.up))

        let results: [TranscriptionResult]
        do {
            results = try await whisperKit.transcribe(
                audioPath: audioURL.path,
                decodeOptions: options,
                callback: { progress in
                    onProgress(min(0.99, Double(progress.windowId) / totalWindows))
                    // Returning false asks WhisperKit to stop early.
                    return !Task.isCancelled
                }
            )
        } catch {
            if Task.isCancelled { throw CancellationError() }
            AppLog.speech.error("Transcription failed: \(error.localizedDescription, privacy: .public)")
            throw AppError.unableToGenerateSubtitles
        }

        try Task.checkCancellation()
        onProgress(1.0)

        let segments = results.flatMap(\.segments).map(Self.makeSegment)
        let text = results.map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)

        return SpeechTranscript(
            text: text,
            detectedLanguageCode: results.first?.language ?? language.languageCode ?? "",
            segments: segments.sorted { $0.startTime < $1.startTime },
            processingTime: Date().timeIntervalSince(started)
        )
    }

    /// Frees the model. Worth calling when a long export needs the memory.
    func unload() async {
        guard let whisperKit else { return }
        await whisperKit.unloadModels()
        self.whisperKit = nil
        loadedVariant = nil
        AppLog.speech.info("Speech model unloaded")
    }

    // MARK: - Conversion

    /// WhisperKit's segment shape into ours. Word timings are carried across whenever
    /// they exist, because karaoke-style highlighting depends on them later.
    private static func makeSegment(_ segment: TranscriptionSegment) -> SubtitleSegment {
        let words = segment.words?.map { timing in
            SubtitleWord(
                word: timing.word.trimmingCharacters(in: .whitespaces),
                startTime: TimeInterval(timing.start),
                endTime: TimeInterval(timing.end)
            )
        }

        return SubtitleSegment(
            startTime: TimeInterval(segment.start),
            endTime: TimeInterval(segment.end),
            text: segment.text.trimmingCharacters(in: .whitespacesAndNewlines),
            words: (words?.isEmpty ?? true) ? nil : words
        )
    }

    private func audioDuration(of url: URL) -> Double {
        // Cheap and good enough to scale progress; a wrong guess only affects the bar.
        guard let file = try? AVAudioFile(forReading: url) else { return 30 }
        let frames = Double(file.length)
        let rate = file.fileFormat.sampleRate
        return rate > 0 ? frames / rate : 30
    }
}

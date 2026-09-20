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
    /// How long the last load took, so it can be reported next to transcription time.
    private var lastPreparationSeconds: TimeInterval = 0

    private init() {}

    var isReady: Bool { whisperKit != nil }
    var currentVariant: String? { loadedVariant }

    // MARK: - Preparation

    /// Downloads the model if needed and loads it. Safe to call repeatedly: once a model
    /// is loaded this returns immediately.
    func prepare(onProgress: @escaping @Sendable (ModelPreparation) -> Void) async throws {
        onProgress(.checking)
        let variant = await ModelManager.resolveVariant()

        if whisperKit != nil, loadedVariant == variant {
            onProgress(.ready)
            return
        }

        // The user changed which model they want: drop the old one before loading the
        // new, so two large models are never resident at once.
        if whisperKit != nil {
            await unload()
        }
        AppLog.speech.info("Preparing speech model \(variant, privacy: .public)")

        let folder = try await ModelManager.ensureAvailable(variant: variant) { fraction in
            onProgress(.downloading(fraction))
        }

        try Task.checkCancellation()
        onProgress(.loading)

        let loadStart = Date()
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
            lastPreparationSeconds = Date().timeIntervalSince(loadStart)
            AppLog.speech.info("Model ready in \(Int(self.lastPreparationSeconds), privacy: .public)s")
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

        // Load the samples ourselves so progress can be reported against the audio's
        // own timeline. Transcribing by file path would load the whole array anyway,
        // so this costs no extra memory and buys a meaningful progress number.
        let samples: [Float]
        do {
            samples = try AudioProcessor.loadAudioAsFloatArray(fromPath: audioURL.path)
        } catch {
            AppLog.speech.error("Could not read extracted audio: \(error.localizedDescription, privacy: .public)")
            throw AppError.unableToGenerateSubtitles
        }

        let totalSeconds = Double(samples.count) / Self.engineSampleRate

        let results: [TranscriptionResult]
        do {
            results = try await whisperKit.transcribe(
                audioArray: samples,
                decodeOptions: options,
                callback: { _ in
                    // Returning false asks WhisperKit to stop early.
                    !Task.isCancelled
                },
                segmentCallback: { discovered in
                    // Each segment carries its end time, so the furthest one is exactly
                    // how much of the audio has been heard.
                    guard totalSeconds > 0, let furthest = discovered.map(\.end).max() else { return }
                    onProgress(min(0.99, max(0, Double(furthest) / totalSeconds)))
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

        let elapsed = Date().timeIntervalSince(started)
        let engineTimings = results.first?.timings
        let timings = SpeechTimings(
            modelPreparation: lastPreparationSeconds,
            specialization: (engineTimings?.encoderSpecializationTime ?? 0)
                + (engineTimings?.decoderSpecializationTime ?? 0),
            audioSeconds: engineTimings?.inputAudioSeconds ?? totalSeconds,
            encoding: engineTimings?.encoding ?? 0,
            decodingLoop: engineTimings?.decodingLoop ?? 0,
            transcription: elapsed
        )
        AppLog.speech.info("Timings — \(timings.summary, privacy: .public)")

        return SpeechTranscript(
            text: text,
            detectedLanguageCode: results.first?.language ?? language.languageCode ?? "",
            segments: segments.sorted { $0.startTime < $1.startTime },
            processingTime: elapsed,
            timings: timings
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

    /// The rate the engine works at, and the rate `AudioExtractor` writes.
    private static let engineSampleRate: Double = 16_000
}

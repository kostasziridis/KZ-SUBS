import Foundation
import Observation

/// Runs the whole subtitle pipeline for one video and reports where it has got to.
///
/// Owns no WhisperKit types: it asks `WhisperService` and `AudioExtractor` to do the
/// work and turns what comes back into state the views can render.
@MainActor
@Observable
final class TranscriptionViewModel {

    let asset: VideoAsset
    let language: AppLanguage

    private(set) var state: TranscriptionState = .idle
    /// Which model stage we are in. `state` carries the progress number; this carries
    /// the reason, so the screen never says "downloading" while merely loading a
    /// model that is already on the device.
    private(set) var preparation: ModelPreparation = .checking
    private(set) var segments: [SubtitleSegment] = []
    private(set) var detectedLanguage: String?
    /// What the engine actually heard. With Auto Detect this is the useful answer,
    /// and it is what the saved project should record.
    private(set) var resolvedLanguage: AppLanguage?
    private(set) var processingTime: TimeInterval = 0
    private(set) var timings: SpeechTimings?
    /// Built once when the run finishes. Rebuilding it would mint a new id each time.
    private(set) var producedProject: SubtitleProject?

    /// One job at a time. A second tap on Generate must not start a parallel run.
    @ObservationIgnored private var job: Task<Void, Never>?
    @ObservationIgnored private var extractedAudioURL: URL?

    init(asset: VideoAsset, language: AppLanguage) {
        self.asset = asset
        self.language = language
    }

    // MARK: - Derived display state

    var isRunning: Bool { state.isBusy }

    var isDownloadingModel: Bool {
        if case .preparingModel = state { return true }
        return false
    }

    /// How far through the video's audio the engine has listened, in seconds.
    var processedSeconds: TimeInterval {
        guard case let .transcribing(progress) = state else { return 0 }
        return asset.duration * progress
    }

    var percentComplete: Int? {
        switch state {
        case let .transcribing(progress): return Int(progress * 100)
        case let .preparingModel(progress): return progress.map { Int($0 * 100) }
        default: return nil
        }
    }

    // MARK: - Running

    func start() {
        guard job == nil else { return }

        segments = []
        detectedLanguage = nil
        resolvedLanguage = nil
        producedProject = nil
        preparation = .checking
        state = .preparingModel(progress: nil)

        job = Task { [weak self] in
            guard let self else { return }
            defer {
                self.job = nil
                self.cleanUpAudio()
            }

            do {
                // The model comes first: it is the slow, possibly-downloading step, and
                // the user should see that named honestly before anything else happens.
                try await WhisperService.shared.prepare { [weak self] preparation in
                    Task { @MainActor in
                        guard let self else { return }
                        self.preparation = preparation
                        switch preparation {
                        case .checking, .loading:
                            self.state = .preparingModel(progress: nil)
                        case let .downloading(fraction):
                            self.state = .preparingModel(progress: fraction)
                        case .ready:
                            break
                        }
                    }
                }

                try Task.checkCancellation()
                self.state = .preparingAudio

                let audioURL = try await AudioExtractor.extractAudio(from: self.asset.url)
                self.extractedAudioURL = audioURL

                try Task.checkCancellation()
                self.state = .transcribing(progress: 0)

                let transcript = try await WhisperService.shared.transcribe(
                    audioURL: audioURL,
                    language: self.language
                ) { [weak self] fraction in
                    Task { @MainActor in
                        guard let self, case .transcribing = self.state else { return }
                        self.state = .transcribing(progress: fraction)
                    }
                }

                try Task.checkCancellation()

                // Reshape the engine's decoding-window segments into readable blocks.
                self.segments = SubtitleSegmenter.makeSubtitles(from: transcript.segments)
                self.detectedLanguage = transcript.detectedLanguageDisplayName
                self.resolvedLanguage = AppLanguage(languageCode: transcript.detectedLanguageCode)
                self.processingTime = transcript.processingTime
                self.timings = transcript.timings
                if !self.segments.isEmpty {
                    var project = SubtitleProject(asset: self.asset, language: self.resolvedLanguage ?? self.language)
                    project.subtitles = self.segments
                    // Remember the whole-line version so a word limit can be undone.
                    project.sourceSubtitles = self.segments
                    self.producedProject = project
                }

                self.state = transcript.segments.isEmpty
                    ? .failed(AppError.unableToGenerateSubtitles)
                    : .completed

                AppLog.speech.info("Produced \(transcript.segments.count, privacy: .public) subtitle(s) in \(Int(transcript.processingTime), privacy: .public)s")

            } catch is CancellationError {
                self.state = .cancelled
            } catch {
                AppLog.speech.error("Pipeline failed: \(error.localizedDescription, privacy: .public)")
                self.state = .failed(error)
            }
        }
    }

    func cancel() {
        job?.cancel()
    }

    // MARK: - Housekeeping

    /// Extracted audio is scratch: it is worthless once transcription is done.
    private func cleanUpAudio() {
        if let url = extractedAudioURL {
            AudioExtractor.discard(url)
            extractedAudioURL = nil
        }
    }
}

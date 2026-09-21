#if DEBUG
import SwiftUI

/// Development harness: runs the speech engine against a bundled clip whose words we
/// already know, so accuracy can be judged at a glance on a real device.
///
/// DEBUG only — never part of a shipping build.
struct SpeechCheckView: View {

    @State private var model = SpeechCheckViewModel()
    @State private var fixture: SpeechFixture = .greek

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                fixturePicker
                expectedCard
                statusCard

                if let transcript = model.transcript {
                    resultCard(transcript)
                    segmentsCard(transcript)
                }

                actions
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .appBackground()
        .navigationTitle("Speech check")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var fixturePicker: some View {
        Picker("Clip", selection: $fixture) {
            ForEach(SpeechFixture.allCases) { item in
                Text(item.title).tag(item)
            }
        }
        .pickerStyle(.segmented)
        .disabled(model.isBusy)
    }

    private var expectedCard: some View {
        GlassCard(radius: AppTheme.controlRadius, padding: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Expected")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.tertiaryText)
                Text(fixture.expectedText)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.secondaryText)
            }
        }
    }

    private var statusCard: some View {
        GlassCard(radius: AppTheme.controlRadius, padding: 16) {
            VStack(alignment: .leading, spacing: 10) {
                Text(model.statusTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)

                if let fraction = model.statusFraction {
                    ProgressView(value: fraction)
                        .tint(AppTheme.accent)
                    Text("\(Int(fraction * 100))%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(AppTheme.secondaryText)
                } else if model.isBusy {
                    ProgressView().tint(.white)
                }

                if let detail = model.statusDetail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(AppTheme.tertiaryText)
                }
            }
        }
    }

    private func resultCard(_ transcript: SpeechTranscript) -> some View {
        GlassCard(radius: AppTheme.controlRadius, padding: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Heard")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.tertiaryText)

                Text(transcript.text.isEmpty ? "(nothing)" : transcript.text)
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    .textSelection(.enabled)

                HStack(spacing: 8) {
                    InfoPill(symbol: "character.bubble", text: transcript.detectedLanguageDisplayName)
                    InfoPill(symbol: "stopwatch", text: String(format: "%.1fs", transcript.processingTime))
                    InfoPill(symbol: "list.bullet", text: "\(transcript.segments.count) segments")
                }
            }
        }
    }

    private func segmentsCard(_ transcript: SpeechTranscript) -> some View {
        GlassCard(radius: AppTheme.controlRadius, padding: 16) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Timings")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.tertiaryText)

                ForEach(transcript.segments) { segment in
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(TimecodeFormatter.precise(segment.startTime)) — \(TimecodeFormatter.precise(segment.endTime))")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(AppTheme.accent)
                        Text(segment.text)
                            .font(.footnote)
                            .foregroundStyle(.white)
                        Text(segment.words.map { "\($0.count) word timings" } ?? "no word timings")
                            .font(.caption2)
                            .foregroundStyle(AppTheme.tertiaryText)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private var actions: some View {
        VStack(spacing: 12) {
            Button {
                model.run(fixture: fixture)
            } label: {
                Label("Transcribe clip", systemImage: "waveform")
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(model.isBusy)

            if model.isBusy {
                Button("Cancel", role: .cancel) { model.cancel() }
                    .buttonStyle(SecondaryButtonStyle())
            }
        }
    }
}

/// A bundled clip plus the words it actually contains.
enum SpeechFixture: String, CaseIterable, Identifiable {
    case greek, english

    var id: String { rawValue }

    var title: String {
        switch self {
        case .greek: return "Ελληνικά"
        case .english: return "English"
        }
    }

    var resourceName: String {
        switch self {
        case .greek: return "test-greek"
        case .english: return "test-english"
        }
    }

    var language: AppLanguage {
        switch self {
        case .greek: return .greek
        case .english: return .english
        }
    }

    var expectedText: String {
        switch self {
        case .greek:
            return "Καλημέρα σε όλους. Σήμερα θα δούμε κάτι καινούργιο με τα υποτιτλισμένα βίντεο."
        case .english:
            return "Hello everyone. Today we are going to look at something new for subtitles on your phone."
        }
    }

    var url: URL? {
        Bundle.main.url(forResource: resourceName, withExtension: "wav")
    }
}

@MainActor
@Observable
final class SpeechCheckViewModel {

    var state: TranscriptionState = .idle
    var transcript: SpeechTranscript?

    @ObservationIgnored private var task: Task<Void, Never>?

    var isBusy: Bool { state.isBusy }

    var statusTitle: String {
        switch state {
        case .idle: return "Ready"
        case .preparingModel: return "Preparing transcription"
        case .preparingAudio: return "Reading audio"
        case .transcribing: return "Listening"
        case .completed: return "Done"
        case .cancelled: return "Cancelled"
        case .failed: return "Failed"
        }
    }

    var statusFraction: Double? {
        switch state {
        case let .preparingModel(progress): return progress
        case let .transcribing(progress): return progress
        default: return nil
        }
    }

    var statusDetail: String? {
        switch state {
        case .preparingModel: return "Downloading the speech model. This happens once."
        case let .failed(error): return (error as? AppError)?.errorDescription ?? error.localizedDescription
        default: return nil
        }
    }

    func run(fixture: SpeechFixture) {
        guard task == nil, let url = fixture.url else {
            if fixture.url == nil { state = .failed(AppError.unableToGenerateSubtitles) }
            return
        }

        transcript = nil
        state = .preparingModel(progress: nil)

        task = Task { [weak self] in
            guard let self else { return }
            defer { self.task = nil }

            do {
                // Whichever engine is selected, so this screen doubles as the way to
                // compare them: same clip, same expected text, different listener.
                let engine = SpeechEngineChoice.current

                let onPreparation: @Sendable (ModelPreparation) -> Void = { [weak self] preparation in
                    Task { @MainActor in
                        guard let self else { return }
                        switch preparation {
                        case .checking: self.state = .preparingModel(progress: nil)
                        case let .downloading(fraction): self.state = .preparingModel(progress: fraction)
                        case .loading: self.state = .preparingModel(progress: nil)
                        case .ready: self.state = .transcribing(progress: 0)
                        }
                    }
                }

                switch engine {
                case .whisper: try await WhisperService.shared.prepare(onProgress: onPreparation)
                case .parakeet: try await ParakeetService.shared.prepare(onProgress: onPreparation)
                }

                try Task.checkCancellation()
                self.state = .transcribing(progress: 0)

                let onTranscriptionProgress: @Sendable (Double) -> Void = { [weak self] fraction in
                    Task { @MainActor in
                        self?.state = .transcribing(progress: fraction)
                    }
                }

                let result: SpeechTranscript
                switch engine {
                case .whisper:
                    result = try await WhisperService.shared.transcribe(
                        audioURL: url,
                        language: fixture.language,
                        onProgress: onTranscriptionProgress
                    )
                case .parakeet:
                    result = try await ParakeetService.shared.transcribe(
                        audioURL: url,
                        language: fixture.language,
                        onProgress: onTranscriptionProgress
                    )
                }

                self.transcript = result
                self.state = .completed
                AppLog.speech.info("Transcript: \(result.text, privacy: .public)")
            } catch is CancellationError {
                self.state = .cancelled
            } catch {
                self.state = .failed(error)
            }
        }
    }

    func cancel() {
        task?.cancel()
    }
}
#endif

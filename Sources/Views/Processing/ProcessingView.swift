import SwiftUI

/// What the user watches while subtitles are made.
///
/// Every stage names itself honestly - a model download says it is a download, and is
/// never shown as transcription progress.
struct ProcessingView: View {

    @Environment(AppState.self) private var appState
    @Environment(AppRouter.self) private var router

    @State private var model: TranscriptionViewModel
    @State private var hasStarted = false

    init(asset: VideoAsset, language: AppLanguage) {
        _model = State(initialValue: TranscriptionViewModel(asset: asset, language: language))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                thumbnail

                switch model.state {
                case .idle, .preparingModel:
                    preparingSection
                case .preparingAudio, .transcribing:
                    listeningSection
                case .completed:
                    completedSection
                case .cancelled:
                    stoppedSection(
                        title: "Stopped",
                        message: "No subtitles were made. You can try again whenever you like.",
                        symbol: "stop.circle"
                    )
                case let .failed(error):
                    stoppedSection(
                        title: (error as? AppError)?.errorDescription ?? "Unable to generate subtitles",
                        message: (error as? AppError)?.recoverySuggestion
                            ?? "Something interrupted the process. Try again.",
                        symbol: (error as? AppError)?.symbolName ?? "exclamationmark.triangle"
                    )
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 36)
        }
        .scrollIndicators(.hidden)
        .appBackground()
        .navigationTitle(model.state.isBusy ? "Working" : "Subtitles")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.visible, for: .navigationBar)
        .navigationBarBackButtonHidden(model.state.isBusy)
        .interactiveDismissDisabled(model.state.isBusy)
        .task {
            // `.task` can run again on reappearance; the job must start exactly once.
            guard !hasStarted else { return }
            hasStarted = true
            model.start()
        }
        .onChange(of: model.segments) { _, segments in
            guard !segments.isEmpty else { return }
            Task { await appState.save(model.makeProject()) }
        }
    }

    // MARK: - Pieces

    private var thumbnail: some View {
        ThumbnailImage(url: model.asset.thumbnailURL)
            .frame(height: 190)
            .frame(maxWidth: .infinity)
            .clipShape(AppTheme.cardShape())
            .overlay {
                AppTheme.cardShape().strokeBorder(AppTheme.hairline, lineWidth: 1)
            }
            .padding(.top, 8)
    }

    private var preparingSection: some View {
        VStack(spacing: 20) {
            WaveformView(isAnimating: true)

            VStack(spacing: 6) {
                Text("Preparing transcription")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                Text(preparationDetail)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.secondaryText)
            }

            if let percent = model.percentComplete {
                progressBlock(fraction: Double(percent) / 100, caption: "\(percent)%")
            } else {
                ProgressView().tint(.white)
            }

            if isDownloading {
                Text("This happens once. After that, subtitles work without internet.")
                    .font(.footnote)
                    .foregroundStyle(AppTheme.tertiaryText)
                    .multilineTextAlignment(.center)
            }

            privacyCard
            cancelButton
        }
    }

    /// Only a real download should be called one.
    private var isDownloading: Bool {
        if case .downloading = model.preparation { return true }
        return false
    }

    private var preparationDetail: String {
        switch model.preparation {
        case .checking: return "Getting things ready…"
        case .downloading: return "Downloading speech model…"
        case .loading, .ready: return "Loading speech model…"
        }
    }

    private var listeningSection: some View {
        VStack(spacing: 20) {
            WaveformView(isAnimating: true)

            VStack(spacing: 6) {
                Text("Generating subtitles")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                Text("Listening to your video…")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.secondaryText)
            }

            if let percent = model.percentComplete {
                progressBlock(
                    fraction: Double(percent) / 100,
                    caption: "\(percent)%",
                    detail: "\(TimecodeFormatter.playhead(model.processedSeconds)) processed / \(TimecodeFormatter.playhead(model.asset.duration))"
                )
            } else {
                ProgressView().tint(.white)
                Text("Reading the audio…")
                    .font(.footnote)
                    .foregroundStyle(AppTheme.tertiaryText)
            }

            privacyCard
            cancelButton
        }
    }

    private var completedSection: some View {
        VStack(spacing: 18) {
            VStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(AppTheme.accent)
                Text("Subtitles ready")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                Text("\(model.segments.count) subtitles · \(model.detectedLanguage ?? "")")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.secondaryText)
            }

            SubtitleListView(segments: model.segments)

            Button {
                router.popToRoot()
            } label: {
                Text("Done")
            }
            .buttonStyle(PrimaryButtonStyle())
        }
    }

    private func stoppedSection(title: String, message: String, symbol: String) -> some View {
        VStack(spacing: 18) {
            Image(systemName: symbol)
                .font(.system(size: 32))
                .foregroundStyle(AppTheme.secondaryText)

            VStack(spacing: 6) {
                Text(title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.secondaryText)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 12) {
                Button {
                    model.start()
                } label: {
                    Label("Try Again", systemImage: "arrow.clockwise")
                }
                .buttonStyle(PrimaryButtonStyle())

                Button {
                    router.popToRoot()
                } label: {
                    Text("Back to Home")
                }
                .buttonStyle(SecondaryButtonStyle())
            }
        }
    }

    private func progressBlock(fraction: Double, caption: String, detail: String? = nil) -> some View {
        VStack(spacing: 8) {
            ProgressView(value: min(max(fraction, 0), 1))
                .tint(AppTheme.accent)

            Text(caption)
                .font(.title2.weight(.semibold).monospacedDigit())
                .foregroundStyle(.white)

            if let detail {
                Text(detail)
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(AppTheme.secondaryText)
            }
        }
    }

    private var privacyCard: some View {
        GlassCard(radius: AppTheme.controlRadius, padding: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Label("Processed entirely on this iPhone", systemImage: "lock.shield.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                Text("Fast. Private. No internet required.")
                    .font(.footnote)
                    .foregroundStyle(AppTheme.secondaryText)
            }
        }
    }

    private var cancelButton: some View {
        Button(role: .cancel) {
            model.cancel()
        } label: {
            Text("Cancel")
        }
        .buttonStyle(SecondaryButtonStyle())
    }
}

#Preview {
    NavigationStack {
        ProcessingView(asset: .sample, language: .greek)
    }
    .environment(AppState.previewEmpty)
    .environment(AppRouter())
    .preferredColorScheme(.dark)
}

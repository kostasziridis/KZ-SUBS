import SwiftUI
import UniformTypeIdentifiers

/// The screen shown after a video is chosen: preview it, set the language,
/// then generate subtitles.
struct VideoImportView: View {

    @Environment(\.dismiss) private var dismiss
    @Environment(AppRouter.self) private var router

    @State private var model: VideoImportViewModel
    @State private var player = VideoPlayerViewModel()
    @State private var isChoosingSubtitleFile = false
    @State private var importFailure: String?

    init(asset: VideoAsset) {
        _model = State(initialValue: VideoImportViewModel(asset: asset))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                VideoPreviewView(
                    model: player,
                    aspectRatio: model.asset.aspectRatio,
                    maxVideoHeight: model.asset.isPortrait ? 520 : nil
                )

                VideoDetailsView(asset: model.asset, fileSizeText: model.fileSizeText)

                languageCard

                if !model.canGenerateSubtitles {
                    noAudioNotice
                }

                actions
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 36)
        }
        .scrollIndicators(.hidden)
        .appBackground()
        .fileImporter(
            isPresented: $isChoosingSubtitleFile,
            allowedContentTypes: Self.subtitleTypes,
            allowsMultipleSelection: false
        ) { result in
            importSubtitles(from: result)
        }
        .alert(
            "Could not import subtitles",
            isPresented: Binding(get: { importFailure != nil }, set: { if !$0 { importFailure = nil } })
        ) {
            Button("OK", role: .cancel) { importFailure = nil }
        } message: {
            Text(importFailure ?? "")
        }
        .navigationTitle(model.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.visible, for: .navigationBar)
        .task {
            player.load(url: model.asset.url, knownDuration: model.asset.duration)
        }
        .onDisappear {
            player.teardown()
        }
    }

    // MARK: - Language

    private var languageCard: some View {
        GlassCard(radius: AppTheme.controlRadius, padding: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Language")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                    Text("Pick the spoken language for better accuracy.")
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                }

                Spacer(minLength: 12)

                Menu {
                    Picker("Language", selection: $model.language) {
                        ForEach(AppLanguage.allCases) { language in
                            Label(language.displayName, systemImage: language.symbolName)
                                .tag(language)
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(model.language.displayName)
                            .font(.subheadline.weight(.medium))
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption2.weight(.bold))
                    }
                    .foregroundStyle(AppTheme.accent)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background {
                        Capsule().fill(AppTheme.elevatedSurface)
                    }
                }
            }
        }
    }

    private var noAudioNotice: some View {
        GlassCard(radius: AppTheme.controlRadius, padding: 16) {
            HStack(spacing: 12) {
                Image(systemName: "speaker.slash.fill")
                    .font(.title3)
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 3) {
                    Text("This video has no sound")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                    Text("Subtitles need speech to work with.")
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                }
            }
        }
    }

    // MARK: - Importing subtitles

    /// `.srt` has no type of its own that every source agrees on, so the extension is
    /// named directly and plain text accepted alongside it.
    private static let subtitleTypes: [UTType] = {
        var types: [UTType] = [.plainText, .text]
        if let srt = UTType(filenameExtension: "srt") { types.insert(srt, at: 0) }
        return types
    }()

    private func importSubtitles(from result: Result<[URL], Error>) {
        guard case let .success(urls) = result, let url = urls.first else {
            if case let .failure(error) = result { importFailure = error.localizedDescription }
            return
        }

        // A file chosen outside the app's own container has to be unlocked first, and
        // locked again whatever happens next.
        let needsUnlocking = url.startAccessingSecurityScopedResource()
        defer { if needsUnlocking { url.stopAccessingSecurityScopedResource() } }

        do {
            let subtitles = try SRTImporter.read(contentsOf: url)
            let language = AppLanguage(languageCode: SRTImporter.languageCode(of: subtitles)) ?? model.language

            var project = SubtitleProject(asset: model.asset, language: language)
            project.subtitles = subtitles
            // The whole-line version, so a words-on-screen limit can be undone later.
            project.sourceSubtitles = subtitles

            // Straight to the style chooser: word-timed subtitles are exactly what the
            // karaoke and spotlight styles want, and this is where they are offered.
            router.push(.stylePicker(project))
        } catch {
            let reason = (error as? LocalizedError)?.failureReason
            importFailure = [error.localizedDescription, reason].compactMap { $0 }.joined(separator: " ")
        }
    }

    // MARK: - Actions

    private var actions: some View {
        VStack(spacing: 12) {
            Button {
                player.pause()
                // Explain the one-time download first, unless a model is already here.
                if ModelManager.isReady() {
                    router.push(.processing(asset: model.asset, language: model.language))
                } else {
                    router.push(.modelSetup(asset: model.asset, language: model.language))
                }
            } label: {
                Label("Generate Subtitles", systemImage: "wand.and.sparkles")
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(!model.canGenerateSubtitles)

            // For a video whose subtitles already exist. Transcribing it again would
            // mean a 600 MB download and a wait, to arrive at something the user is
            // holding in their hand.
            Button {
                player.pause()
                isChoosingSubtitleFile = true
            } label: {
                Label("Import subtitle file", systemImage: "doc.text")
            }
            .buttonStyle(SecondaryButtonStyle())

            Button {
                player.pause()
                dismiss()
            } label: {
                Text("Choose Another Video")
            }
            .buttonStyle(SecondaryButtonStyle())

            PrivacyBadge(text: String(localized: "Processed entirely on this iPhone"))
                .padding(.top, 4)
        }
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        VideoImportView(asset: .sample)
    }
    .environment(AppRouter())
    .preferredColorScheme(.dark)
}
#endif

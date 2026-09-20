import SwiftUI

/// The screen shown after a video is chosen: preview it, set the language,
/// then generate subtitles.
struct VideoImportView: View {

    @Environment(\.dismiss) private var dismiss
    @Environment(AppRouter.self) private var router

    @State private var model: VideoImportViewModel
    @State private var player = VideoPlayerViewModel()

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

    // MARK: - Actions

    private var actions: some View {
        VStack(spacing: 12) {
            Button {
                player.pause()
                router.push(.processing(asset: model.asset, language: model.language))
            } label: {
                Label("Generate Subtitles", systemImage: "wand.and.sparkles")
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(!model.canGenerateSubtitles)

            Button {
                player.pause()
                dismiss()
            } label: {
                Text("Choose Another Video")
            }
            .buttonStyle(SecondaryButtonStyle())

            PrivacyBadge(text: "Processed entirely on this iPhone")
                .padding(.top, 4)
        }
    }
}

#Preview {
    NavigationStack {
        VideoImportView(asset: .sample)
    }
    .environment(AppRouter())
    .preferredColorScheme(.dark)
}

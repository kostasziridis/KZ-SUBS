import SwiftUI

/// Turns a finished project into files: a video with the subtitles burned in, and an
/// .srt for everywhere else.
struct ExportView: View {

    @State private var model: ExportViewModel

    init(project: SubtitleProject) {
        _model = State(initialValue: ExportViewModel(project: project))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                summary

                switch model.state {
                case .idle, .cancelled, .failed:
                    startSection
                case .preparing, .rendering, .savingToPhotos:
                    progressSection
                case .completed:
                    readySection
                }

                subtitleFileSection
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .appBackground()
        .navigationTitle(isReady ? "Your video is ready" : "Export")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.visible, for: .navigationBar)
        .navigationBarBackButtonHidden(model.isWorking)
        .alert(
            model.error?.errorDescription ?? "Something went wrong",
            isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } }),
            presenting: model.error
        ) { _ in
            Button("OK", role: .cancel) { }
        } message: { error in
            Text(error.recoverySuggestion ?? "")
        }
    }

    private var isReady: Bool {
        if case .completed = model.state { return true }
        return false
    }

    // MARK: - Summary

    private var summary: some View {
        GlassCard(radius: AppTheme.controlRadius, padding: 16) {
            HStack(spacing: 14) {
                ThumbnailImage(url: model.project.thumbnailURL)
                    .frame(width: 92, height: 62)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.tileRadius, style: .continuous))

                VStack(alignment: .leading, spacing: 5) {
                    Text(model.project.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    Text("\(TimecodeFormatter.duration(model.project.duration)) · \(model.resolutionText)")
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)

                    Text("\(model.project.subtitles.count) subtitles · \(model.project.language.displayName)")
                        .font(.caption2)
                        .foregroundStyle(AppTheme.tertiaryText)
                }

                Spacer(minLength: 0)
            }
        }
    }

    // MARK: - Start

    private var startSection: some View {
        VStack(spacing: 12) {
            Button {
                model.exportVideo()
            } label: {
                Label("Create video with subtitles", systemImage: "film.badge.plus")
            }
            .buttonStyle(PrimaryButtonStyle())

            Text("Subtitles are drawn permanently into a new video. Your original is untouched.")
                .font(.caption2)
                .foregroundStyle(AppTheme.tertiaryText)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Progress

    private var progressSection: some View {
        GlassCard(radius: AppTheme.controlRadius, padding: 18) {
            VStack(spacing: 12) {
                Text(model.state.isSaving ? "Saving to Photos" : "Adding subtitles to your video")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)

                if let progress = model.progress {
                    ProgressView(value: progress)
                        .tint(AppTheme.accent)
                    Text("\(Int(progress * 100))%")
                        .font(.title3.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.white)
                } else {
                    ProgressView().tint(.white)
                }

                Button(role: .cancel) {
                    model.cancel()
                } label: {
                    Text("Cancel")
                }
                .buttonStyle(SecondaryButtonStyle())
            }
        }
    }

    // MARK: - Ready

    private var readySection: some View {
        VStack(spacing: 12) {
            if model.savedToPhotos {
                Label("Saved to Photos", systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.accent)
            }

            if model.simplifiedHighlighting {
                Label(
                    "This video was long, so words are not highlighted one by one in the export.",
                    systemImage: "info.circle"
                )
                .font(.caption2)
                .foregroundStyle(AppTheme.tertiaryText)
                .multilineTextAlignment(.leading)
            }

            Button {
                Task { await model.saveToPhotos() }
            } label: {
                Label("Save to Photos", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(PrimaryButtonStyle())

            if let url = model.exportedVideoURL {
                ShareLink(item: url) {
                    Label("Share video", systemImage: "square.and.arrow.up")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background {
                            RoundedRectangle(cornerRadius: AppTheme.controlRadius, style: .continuous)
                                .fill(.ultraThinMaterial)
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: AppTheme.controlRadius, style: .continuous)
                                .strokeBorder(AppTheme.hairline, lineWidth: 1)
                        }
                }
                .foregroundStyle(.white)
            }
        }
    }

    // MARK: - Subtitle file

    private var subtitleFileSection: some View {
        GlassCard(radius: AppTheme.controlRadius, padding: 16) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Subtitle file")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)

                Text("An .srt file works with YouTube, Premiere, VLC and most editors.")
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)

                if let url = model.subtitleFileURL {
                    ShareLink(item: url) {
                        Label("Share \(url.lastPathComponent)", systemImage: "square.and.arrow.up")
                            .font(.footnote.weight(.medium))
                    }
                    .tint(AppTheme.accent)
                } else {
                    Button {
                        model.exportSubtitleFile()
                    } label: {
                        Label("Create .srt file", systemImage: "doc.text")
                            .font(.footnote.weight(.medium))
                    }
                    .tint(AppTheme.accent)
                    .disabled(model.project.subtitles.isEmpty)
                }
            }
        }
    }
}

private extension ExportState {
    var isSaving: Bool {
        if case .savingToPhotos = self { return true }
        return false
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        ExportView(project: .sample)
    }
    .preferredColorScheme(.dark)
}
#endif

import SwiftUI

/// Shown once subtitles exist: pick a look before opening the editor.
///
/// The styles are the most interesting thing the app does, and leaving them behind a
/// two-letter toolbar button meant most people would never find them. Here each one is
/// previewed on the user's own video, playing their own words.
struct CaptionStylePickerView: View {

    @Environment(AppState.self) private var appState
    @Environment(AppRouter.self) private var router

    let project: SubtitleProject

    @State private var style: CaptionStyle
    @State private var player = VideoPlayerViewModel()
    @State private var hasStarted = false

    init(project: SubtitleProject) {
        self.project = project
        _style = State(initialValue: project.captionStyle)
    }

    /// The stretch of video replayed underneath, chosen to contain speech so the
    /// word-by-word styles actually show what they do.
    private var loop: ClosedRange<TimeInterval> {
        guard let first = project.subtitles.first else { return 0...min(4, project.duration) }
        let end = project.subtitles
            .prefix(3)
            .last?
            .endTime ?? first.endTime
        return first.startTime...max(first.startTime + 1, end)
    }

    private var aspectRatio: CGFloat {
        let size = project.pixelSize
        guard size.height > 0 else { return 16.0 / 9.0 }
        return size.width / size.height
    }

    var body: some View {
        VStack(spacing: 0) {
            preview
            styleStrip
            actions
        }
        .appBackground()
        .navigationTitle("Choose a style")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.visible, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        .task {
            guard !hasStarted else { return }
            hasStarted = true
            player.observationInterval = 1.0 / 30.0
            player.load(url: project.videoURL, knownDuration: project.duration)
        }
        .onChange(of: player.isReady) { _, isReady in
            // Playback has to wait for the item to be ready; asking straight after
            // `load` is ignored, and the preview would sit frozen on black.
            guard isReady else { return }
            player.seek(to: loop.lowerBound, precise: true)
            player.play()
        }
        .onDisappear { player.teardown() }
    }

    // MARK: - Preview

    private var preview: some View {
        VideoPreviewView(
            model: player,
            aspectRatio: aspectRatio,
            maxVideoHeight: project.pixelSize.height > project.pixelSize.width ? 380 : nil,
            showsControls: false,
            videoOverlay: {
                StyleLoopLayer(player: player, project: project, style: style, loop: loop, aspectRatio: aspectRatio)
            }
        )
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 16)
    }

    // MARK: - Styles

    private var styleStrip: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Styles")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(AppTheme.secondaryText)
                .padding(.horizontal, 20)

            ScrollView(.horizontal) {
                HStack(spacing: 12) {
                    ForEach(CaptionStyle.Preset.allCases) { preset in
                        styleCard(preset)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 4)
            }
            .scrollIndicators(.hidden)
        }
    }

    private func styleCard(_ preset: CaptionStyle.Preset) -> some View {
        let isSelected = style.preset == preset

        return Button {
            withAnimation(.snappy(duration: 0.22)) {
                // Keep where the caption sits; only the look changes.
                var replacement = CaptionStyle.preset(preset)
                replacement.horizontalPosition = style.horizontalPosition
                replacement.verticalPosition = style.verticalPosition
                replacement.isUppercased = style.isUppercased
                style = replacement
            }
        } label: {
            VStack(spacing: 8) {
                ZStack {
                    LinearGradient(
                        colors: [Color(red: 0.17, green: 0.18, blue: 0.26), Color(red: 0.08, green: 0.08, blue: 0.13)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                    CaptionOverlayView(
                        segment: CaptionStylePreview.placeholder,
                        style: sampleStyle(for: preset),
                        currentTime: 1.4
                    )
                }
                .frame(width: 128, height: 84)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(isSelected ? AppTheme.accent : AppTheme.hairline, lineWidth: isSelected ? 2.5 : 1)
                }

                Text(preset.displayName)
                    .font(.caption.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? .white : AppTheme.secondaryText)
            }
        }
        .buttonStyle(.plain)
    }

    /// The card is small, so the caption is scaled up to stay legible in it.
    private func sampleStyle(for preset: CaptionStyle.Preset) -> CaptionStyle {
        var sample = CaptionStyle.preset(preset)
        sample.referenceFontSize = max(sample.referenceFontSize, 150)
        sample.verticalPosition = 0.5
        sample.horizontalPosition = 0.5
        return sample
    }

    // MARK: - Actions

    private var actions: some View {
        VStack(spacing: 10) {
            Button {
                var updated = project
                updated.captionStyle = style
                Task {
                    await appState.save(updated)
                    router.replaceStack(with: .editor(updated))
                }
            } label: {
                Label("Use this style", systemImage: "checkmark")
            }
            .buttonStyle(PrimaryButtonStyle())

            Text("You can change everything later — colours, size, position and more.")
                .font(.caption2)
                .foregroundStyle(AppTheme.tertiaryText)
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 8)
    }
}

/// Draws the caption and keeps the preview looping over the same few seconds.
private struct StyleLoopLayer: View {
    let player: VideoPlayerViewModel
    let project: SubtitleProject
    let style: CaptionStyle
    let loop: ClosedRange<TimeInterval>
    let aspectRatio: CGFloat

    var body: some View {
        CaptionOverlayView(
            segment: segment(at: player.currentTime),
            style: style,
            currentTime: player.currentTime,
            contentAspectRatio: aspectRatio
        )
        .onChange(of: player.currentTime) { _, time in
            if time >= loop.upperBound || time < loop.lowerBound - 0.5 {
                player.seek(to: loop.lowerBound, precise: true)
                player.play()
            }
        }
    }

    private func segment(at time: TimeInterval) -> SubtitleSegment? {
        project.subtitles.first { time >= $0.startTime && time < $0.endTime }
    }
}

#Preview {
    NavigationStack {
        CaptionStylePickerView(project: .sample)
    }
    .environment(AppState.previewEmpty)
    .environment(AppRouter())
    .preferredColorScheme(.dark)
}

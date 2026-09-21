import SwiftUI

/// The reusable video surface: player, tap-to-play, scrubber and timecodes.
///
/// Captions are drawn by the caller with `.overlay`, which keeps this view free of
/// any subtitle knowledge.
struct VideoPreviewView<Overlay: View>: View {

    @Bindable var model: VideoPlayerViewModel
    var aspectRatio: CGFloat = 16.0 / 9.0
    /// Caps how tall a portrait video may grow inside a scrolling layout.
    var maxVideoHeight: CGFloat? = nil
    var showsControls: Bool = true
    /// Drawn over the picture itself rather than over the whole component. Captions
    /// have to be positioned against the video; measuring them against the transport
    /// bar as well puts them lower than they will be in the exported file.
    @ViewBuilder var videoOverlay: Overlay

    @State private var controlsVisible = true
    @State private var hideTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 14) {
            videoSurface

            if showsControls {
                transportBar
            }
        }
    }

    // MARK: - Video

    private var videoSurface: some View {
        ZStack {
            PlayerLayerView(player: model.player)

            if !model.isReady {
                ProgressView()
                    .controlSize(.large)
                    .tint(.white)
            }

            if showsControls && controlsVisible {
                playPauseOverlay
            }
        }
        .aspectRatio(aspectRatio, contentMode: .fit)
        // A full-width stage, so every video sits in a card of the same width whatever
        // its shape. Portrait clips letterbox inside it; `maxVideoHeight` decides how
        // tall that stage gets, and so how wide a portrait video ends up.
        .frame(maxWidth: .infinity, maxHeight: maxVideoHeight)
        .overlay { videoOverlay }
        .background(Color.black)
        .clipShape(AppTheme.cardShape(AppTheme.cardRadius))
        .overlay {
            AppTheme.cardShape(AppTheme.cardRadius)
                .strokeBorder(AppTheme.hairline, lineWidth: 1)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeOut(duration: 0.2)) { controlsVisible.toggle() }
            scheduleControlsHide()
        }
    }

    private var playPauseOverlay: some View {
        Button {
            model.togglePlayback()
            scheduleControlsHide()
        } label: {
            Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 66, height: 66)
                .background {
                    Circle().fill(.ultraThinMaterial)
                }
                .overlay {
                    Circle().strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .disabled(!model.isReady)
        .accessibilityLabel(model.isPlaying ? Text("Pause") : Text("Play"))
        .transition(.opacity.combined(with: .scale(scale: 0.9)))
    }

    // MARK: - Transport

    private var transportBar: some View {
        VStack(spacing: 6) {
            Slider(
                value: Binding(
                    get: { model.currentTime },
                    set: { model.seek(to: $0) }
                ),
                in: 0...max(model.duration, 0.01),
                onEditingChanged: { editing in
                    model.isScrubbing = editing
                    if !editing {
                        model.seek(to: model.currentTime, precise: true)
                    }
                }
            )
            .tint(AppTheme.accent)
            .disabled(!model.isReady)

            HStack {
                Text(TimecodeFormatter.playhead(model.currentTime))
                Spacer()
                Text(TimecodeFormatter.playhead(model.duration))
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(AppTheme.secondaryText)
        }
    }

    // MARK: - Controls auto-hide

    private func scheduleControlsHide() {
        hideTask?.cancel()
        guard model.isPlaying, controlsVisible else { return }
        hideTask = Task {
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.25)) { controlsVisible = false }
        }
    }
}

extension VideoPreviewView where Overlay == EmptyView {
    init(
        model: VideoPlayerViewModel,
        aspectRatio: CGFloat = 16.0 / 9.0,
        maxVideoHeight: CGFloat? = nil,
        showsControls: Bool = true
    ) {
        self.init(
            model: model,
            aspectRatio: aspectRatio,
            maxVideoHeight: maxVideoHeight,
            showsControls: showsControls,
            videoOverlay: { EmptyView() }
        )
    }
}

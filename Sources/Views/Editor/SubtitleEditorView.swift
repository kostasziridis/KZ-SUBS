import SwiftUI

/// The main working screen: watch the video with its subtitles on it, and change them.
struct SubtitleEditorView: View {

    @Environment(AppState.self) private var appState
    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss

    @State private var model: SubtitleEditorViewModel
    @State private var player = VideoPlayerViewModel()
    @State private var editingSegment: SubtitleSegment?
    @State private var showsStyleEditor = false

    init(project: SubtitleProject, onSave: @escaping (SubtitleProject) async -> Void) {
        _model = State(initialValue: SubtitleEditorViewModel(project: project, onSave: onSave))
    }

    private var aspectRatio: CGFloat {
        let size = model.project.pixelSize
        guard size.height > 0 else { return 16.0 / 9.0 }
        return size.width / size.height
    }

    private var isPortrait: Bool { model.project.pixelSize.height > model.project.pixelSize.width }

    var body: some View {
        VStack(spacing: 0) {
            playerSection
            Divider().overlay(AppTheme.hairline)
            subtitleSection
        }
        .appBackground()
        .navigationTitle(model.project.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showsStyleEditor = true
                } label: {
                    Image(systemName: "textformat")
                }
                .tint(AppTheme.accent)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    player.pause()
                    Task {
                        // Persist the edits first, so the export and the saved project
                        // are the same thing.
                        await model.saveNow()
                        router.push(.export(model.currentProject()))
                    }
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .tint(AppTheme.accent)
                .disabled(model.segments.isEmpty)
            }
        }
        .task {
            // Word highlighting needs finer steps than a scrubber does.
            player.observationInterval = 1.0 / 30.0
            player.load(url: model.project.videoURL, knownDuration: model.project.duration)
        }
        .onChange(of: model.captionStyle.maxWordsOnScreen) { _, limit in
            model.applyWordLimit(limit)
        }
        .onDisappear {
            player.teardown()
            Task { await model.saveNow() }
        }
        .sheet(item: $editingSegment) { segment in
            SubtitleEditSheet(
                segment: segment,
                canGoPrevious: previousSegment(before: segment) != nil,
                canGoNext: nextSegment(after: segment) != nil,
                onChange: { model.update($0) },
                onDelete: {
                    model.delete(segment)
                    editingSegment = nil
                },
                onPrevious: { editingSegment = previousSegment(before: segment) },
                onNext: { editingSegment = nextSegment(after: segment) },
                onSeek: { player.seek(to: $0, precise: true) }
            )
        }
        .sheet(isPresented: $showsStyleEditor) {
            CaptionStyleView(
                style: Binding(
                    get: { model.captionStyle },
                    set: { model.captionStyle = $0 }
                ),
                sampleSegment: model.activeSegment ?? model.segments.first
            )
            .presentationDetents([.medium, .large])
            .presentationBackground(.ultraThinMaterial)
        }
    }

    // MARK: - Player

    @ViewBuilder
    private var playerSection: some View {
        VideoPreviewView(
            model: player,
            aspectRatio: aspectRatio,
            maxVideoHeight: isPortrait ? 360 : nil
        )
        .overlay {
            // Its own view, so 30 time updates a second redraw the captions and
            // nothing else on this screen.
            CaptionLayer(player: player, model: model)
        }
        .overlay(alignment: .trailing) {
            CaptionSizeSlider(
                value: Binding(
                    get: { model.captionStyle.referenceFontSize },
                    set: { model.captionStyle.referenceFontSize = $0 }
                ),
                range: 24...140
            )
            .frame(height: 170)
            .padding(.trailing, 12)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)

        Text("Drag the caption to move it · pinch or use the slider to resize")
            .font(.caption2)
            .foregroundStyle(AppTheme.tertiaryText)
            .frame(maxWidth: .infinity)
            .padding(.bottom, 12)
    }

    // MARK: - List

    private var subtitleSection: some View {
        VStack(spacing: 0) {
            HStack {
                Text("\(model.segments.count) subtitles")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(AppTheme.secondaryText)
                Spacer()
                Button {
                    let created = model.addSegment(at: player.currentTime, limit: max(player.duration, model.project.duration))
                    editingSegment = created
                } label: {
                    Label("Add", systemImage: "plus.circle.fill")
                        .font(.footnote.weight(.semibold))
                }
                .tint(AppTheme.accent)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)

            ScrollViewReader { scroll in
                ScrollView {
                    SubtitleListView(
                        segments: model.segments,
                        activeSegmentID: model.activeSegmentID
                    ) { segment in
                        model.selectedSegmentID = segment.id
                        // Land just inside the subtitle: seeking to its exact start can
                        // settle a hair before it, leaving the caption off screen.
                        player.seek(to: segment.startTime + 0.05, precise: true)
                        editingSegment = segment
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
                }
                .scrollIndicators(.hidden)
                .onChange(of: model.activeSegmentID) { _, id in
                    guard let id else { return }
                    withAnimation(.easeInOut(duration: 0.25)) {
                        scroll.scrollTo(id, anchor: .center)
                    }
                }
            }

            if model.segments.isEmpty {
                emptyState
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "captions.bubble")
                .font(.system(size: 26))
                .foregroundStyle(AppTheme.tertiaryText)
            Text("No subtitles yet")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.secondaryText)
            Text("Tap Add to write one.")
                .font(.footnote)
                .foregroundStyle(AppTheme.tertiaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    // MARK: - Neighbours

    private func previousSegment(before segment: SubtitleSegment) -> SubtitleSegment? {
        guard let index = model.index(of: segment), index > 0 else { return nil }
        return model.segments[index - 1]
    }

    private func nextSegment(after segment: SubtitleSegment) -> SubtitleSegment? {
        guard let index = model.index(of: segment), index + 1 < model.segments.count else { return nil }
        return model.segments[index + 1]
    }
}

/// The captions drawn over the video.
///
/// Separated out on purpose: it reads `currentTime`, which changes 30 times a second,
/// and SwiftUI then only has to redraw this layer.
private struct CaptionLayer: View {
    let player: VideoPlayerViewModel
    let model: SubtitleEditorViewModel

    var body: some View {
        CaptionOverlayView(
            segment: model.segment(at: player.currentTime),
            style: model.captionStyle,
            currentTime: player.currentTime,
            editing: Binding(
                get: { model.captionStyle },
                set: { model.captionStyle = $0 }
            )
        )
        .onChange(of: player.currentTime) { _, time in
            // Only writes when the subtitle actually changes.
            model.updateActiveSegment(at: time)
        }
    }
}

#Preview {
    NavigationStack {
        SubtitleEditorView(project: .sample) { _ in }
    }
    .environment(AppState.previewEmpty)
    .preferredColorScheme(.dark)
}

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
    @State private var spelling = SpellReviewViewModel()
    @State private var showsSpelling = false

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
        // The keyboard must not resize the layout: squeezing the video is exactly
        // what ruins editing a caption on top of it. Let it cover the list instead.
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .navigationTitle(model.project.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showsStyleEditor = true
                } label: {
                    // The word on its own. An icon beside it only invited reading the
                    // "Aa" as the button and the word as a caption for it.
                    Text("Style")
                        .font(.body.weight(.medium))
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
            // The Greek dictionary takes a moment to unpack; do it now rather than
            // when the first word is looked at.
            SpellCheck.prepare()
            // Word highlighting needs finer steps than a scrubber does.
            player.observationInterval = 1.0 / 30.0
            player.load(url: model.project.videoURL, knownDuration: model.project.duration)
        }
        .onChange(of: model.captionStyle.maxWordsOnScreen) { _, limit in
            model.applyWordLimit(limit)
        }
        .task(id: model.segments.map(\.text).joined(separator: "\u{1}")) {
            // Not while the review is open. Applying a correction changes a subtitle,
            // which would otherwise start the whole scan again underneath the list the
            // user is working through - the fix they just made pulling the list out
            // from under them.
            guard !showsSpelling else { return }
            spelling.check(model.segments)
        }
        .onChange(of: showsSpelling) { _, isOpen in
            // Catching up on whatever changed while it was open, now that nobody is
            // looking at the list.
            guard !isOpen else { return }
            spelling.check(model.segments)
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
        .sheet(isPresented: $showsSpelling) {
            SpellReviewView(
                model: spelling,
                onCorrect: { finding, replacement in
                    correct(finding, with: replacement)
                },
                onGoTo: { finding in
                    model.selectedSegmentID = finding.segmentID
                    player.seek(to: finding.startTime + 0.05, precise: true)
                }
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
            maxVideoHeight: isPortrait ? 360 : nil,
            videoOverlay: {
                // Its own view, so 30 time updates a second redraw the captions and
                // nothing else on this screen.
                CaptionLayer(player: player, model: model, aspectRatio: aspectRatio)
            }
        )
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

    /// Says how many words want looking at, so a spelling pass is something the user
    /// is told about rather than something they have to think to run.
    @ViewBuilder
    private var spellingButton: some View {
        if !model.segments.isEmpty {
            Button {
                spelling.check(model.segments)
                showsSpelling = true
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: spelling.count > 0 ? "text.badge.xmark" : "textformat.abc.dottedunderline")
                    if spelling.count > 0 {
                        Text("\(spelling.count)")
                            .font(.footnote.weight(.semibold).monospacedDigit())
                    }
                }
                .font(.footnote.weight(.semibold))
            }
            .tint(spelling.count > 0 ? .orange : AppTheme.accent)
        }
    }

    // MARK: - List

    private var subtitleSection: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(model.segments.count) subtitles")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(AppTheme.secondaryText)
                    Text("Tap a subtitle to jump to it")
                        .font(.caption2)
                        .foregroundStyle(AppTheme.tertiaryText)
                }
                Spacer()

                spellingButton

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
                        activeSegmentID: model.activeSegmentID,
                        onSelect: { segment in
                            model.selectedSegmentID = segment.id
                            // Land just inside the subtitle: seeking to its exact start
                            // can settle a hair before it, leaving the caption off screen.
                            player.seek(to: segment.startTime + 0.05, precise: true)
                        },
                        onEdit: { segment in
                            model.selectedSegmentID = segment.id
                            player.seek(to: segment.startTime + 0.05, precise: true)
                            editingSegment = segment
                        }
                    )
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

    // MARK: - Corrections

    /// Applies one correction from the review.
    ///
    /// Through `renameWord` wherever there are word timings, so the moment the word is
    /// spoken does not move and the styles that light up words keep working. A subtitle
    /// written by hand has no timings, so there the text is edited instead.
    private func correct(_ finding: SpellFinding, with replacement: String) {
        guard var segment = model.segments.first(where: { $0.id == finding.segmentID }) else { return }

        // Carrying over the capital and the punctuation the original word wore.
        let shaped = SpellCheck.shaped(replacement, like: finding.word)

        if let wordID = finding.wordID {
            segment.renameWord(id: wordID, to: shaped)
        } else {
            let corrected = segment.text
                .split(whereSeparator: \.isWhitespace)
                .map { $0 == finding.word ? shaped : String($0) }
                .joined(separator: " ")
            segment.setText(corrected)
        }

        model.update(segment)
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
    let aspectRatio: CGFloat

    /// The words as they stood when typing on the video began.
    ///
    /// Every keystroke re-matches the text against these rather than against the
    /// previous keystroke's result, so a word that is deleted and typed again comes
    /// back with the timing it was originally spoken at.
    @State private var wordsBeforeEditing: (segment: SubtitleSegment.ID, words: [SubtitleWord])?

    var body: some View {
        let current = model.segment(at: player.currentTime)

        CaptionOverlayView(
            segment: current,
            style: model.captionStyle,
            currentTime: player.currentTime,
            editing: Binding(
                get: { model.captionStyle },
                set: { model.captionStyle = $0 }
            ),
            // Read back through the model rather than the captured copy, so the field
            // reflects every keystroke that has already been applied.
            text: current.map { segment in
                Binding(
                    get: { model.segments.first { $0.id == segment.id }?.text ?? segment.text },
                    set: { newText in
                        guard var edited = model.segments.first(where: { $0.id == segment.id }) else { return }

                        let original: [SubtitleWord]
                        if let held = wordsBeforeEditing, held.segment == segment.id {
                            original = held.words
                        } else {
                            original = edited.words ?? []
                            wordsBeforeEditing = (segment.id, original)
                        }

                        edited.words = original.isEmpty ? nil : original
                        // Not `edited.text =`: the styles that light up words one by
                        // one are drawn from the words, so a correction written only
                        // into the text would never reach the screen.
                        edited.setText(newText)
                        model.update(edited)
                    }
                )
            },
            onBeginTextEditing: { player.pause() },
            onEndTextEditing: { wordsBeforeEditing = nil },
            contentAspectRatio: aspectRatio
        )
        .onChange(of: player.currentTime) { _, time in
            // Only writes when the subtitle actually changes.
            model.updateActiveSegment(at: time)
        }
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        SubtitleEditorView(project: .sample) { _ in }
    }
    .environment(AppState.previewEmpty)
    .preferredColorScheme(.dark)
}
#endif

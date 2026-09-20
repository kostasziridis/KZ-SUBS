import Foundation
import Observation

/// Holds the project being edited: its subtitles, its styling, and which subtitle is
/// currently selected. Saves are debounced so dragging a slider does not write to disk
/// on every frame.
@MainActor
@Observable
final class SubtitleEditorViewModel {

    private(set) var project: SubtitleProject
    var segments: [SubtitleSegment] {
        didSet { scheduleSave() }
    }
    var captionStyle: CaptionStyle {
        didSet { scheduleSave() }
    }

    /// The subtitle the user picked, which is not necessarily the one playing.
    var selectedSegmentID: SubtitleSegment.ID?
    /// The subtitle under the playhead.
    private(set) var activeSegmentID: SubtitleSegment.ID?

    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private let onSave: (SubtitleProject) async -> Void

    init(project: SubtitleProject, onSave: @escaping (SubtitleProject) async -> Void) {
        self.project = project
        self.segments = project.subtitles
        self.captionStyle = project.captionStyle
        self.onSave = onSave
    }

    // MARK: - Playback synchronisation

    /// The subtitle showing at `time`, or nil in a gap.
    func segment(at time: TimeInterval) -> SubtitleSegment? {
        // Segments are ordered and non-overlapping, so a binary search keeps this cheap
        // even when it runs on every playback tick of a long video.
        var low = 0
        var high = segments.count - 1
        while low <= high {
            let mid = (low + high) / 2
            let candidate = segments[mid]
            if time < candidate.startTime {
                high = mid - 1
            } else if time >= candidate.endTime {
                low = mid + 1
            } else {
                return candidate
            }
        }
        return nil
    }

    /// Updates the active subtitle, and reports whether it actually changed - so the
    /// caller can avoid touching SwiftUI state on every tick.
    @discardableResult
    func updateActiveSegment(at time: TimeInterval) -> Bool {
        let id = segment(at: time)?.id
        guard id != activeSegmentID else { return false }
        activeSegmentID = id
        return true
    }

    var activeSegment: SubtitleSegment? {
        guard let activeSegmentID else { return nil }
        return segments.first { $0.id == activeSegmentID }
    }

    var selectedSegment: SubtitleSegment? {
        guard let selectedSegmentID else { return nil }
        return segments.first { $0.id == selectedSegmentID }
    }

    func index(of segment: SubtitleSegment) -> Int? {
        segments.firstIndex { $0.id == segment.id }
    }

    // MARK: - Editing

    func update(_ segment: SubtitleSegment) {
        guard let index = index(of: segment) else { return }
        var edited = segment
        // Never let an edit invert or collapse a subtitle.
        edited.endTime = max(edited.endTime, edited.startTime + 0.2)
        segments[index] = edited
        segments.sort { $0.startTime < $1.startTime }
    }

    func delete(_ segment: SubtitleSegment) {
        segments.removeAll { $0.id == segment.id }
        if selectedSegmentID == segment.id { selectedSegmentID = nil }
        if activeSegmentID == segment.id { activeSegmentID = nil }
    }

    /// Inserts a new subtitle at the playhead, fitted into whatever gap is available.
    @discardableResult
    func addSegment(at time: TimeInterval, duration: TimeInterval = 2, limit: TimeInterval) -> SubtitleSegment {
        let start = min(max(0, time), max(0, limit - 0.4))
        // Stop at the next subtitle so a new one never overlaps its neighbour.
        let nextStart = segments.first { $0.startTime > start }?.startTime ?? limit
        let end = min(start + duration, max(start + 0.4, nextStart))

        let segment = SubtitleSegment(startTime: start, endTime: end, text: "New subtitle")
        segments.append(segment)
        segments.sort { $0.startTime < $1.startTime }
        selectedSegmentID = segment.id
        return segment
    }

    func applyPreset(_ preset: CaptionStyle.Preset) {
        captionStyle = .preset(preset)
    }

    /// Re-splits the subtitles so at most `limit` words show at once, or restores the
    /// whole lines when `limit` is nil.
    ///
    /// Always works from the originals, so switching between limits does not split
    /// what is already split.
    func applyWordLimit(_ limit: Int?) {
        let base = project.sourceSubtitles ?? segments
        if project.sourceSubtitles == nil {
            project.sourceSubtitles = segments
        }

        let updated = limit.map { SubtitleSegmenter.limitWords(base, maxWords: $0) } ?? base
        guard updated != segments else { return }
        segments = updated
        selectedSegmentID = nil
        activeSegmentID = nil
    }

    // MARK: - Saving

    /// Waits for the edits to settle before writing, so a drag is one save, not fifty.
    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled, let self else { return }
            await self.saveNow()
        }
    }

    func saveNow() async {
        project.subtitles = segments
        project.captionStyle = captionStyle
        project.updatedAt = Date()
        await onSave(project)
    }
}

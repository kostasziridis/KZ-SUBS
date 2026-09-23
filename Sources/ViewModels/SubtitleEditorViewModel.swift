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

    /// Somewhere to put the subtitles back.
    ///
    /// Snapshots rather than inverse operations: the subtitles of one video are a few
    /// hundred small structs, so keeping whole copies costs almost nothing and cannot
    /// drift out of step with the edits the way a hand-written undo for each operation
    /// eventually does.
    private struct Snapshot {
        let label: String
        let segments: [SubtitleSegment]
        /// Edits that belong together carry the same key, so typing a word does not
        /// leave one undo step per keystroke.
        let coalescingKey: String?
        let madeAt: Date
    }

    @ObservationIgnored private var undoStack: [Snapshot] = []
    /// Deep enough to cover a session's worth of mistakes, shallow enough that nobody
    /// notices the memory.
    private static let undoDepth = 40

    private(set) var undoLabel: String?
    var canUndo: Bool { undoLabel != nil }

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

    // MARK: - Undo

    /// Records the subtitles as they are, before whatever is about to change them.
    ///
    /// - Parameter coalescingKey: successive edits sharing a key within a couple of
    ///   seconds are one step. Typing passes the subtitle's id; a deletion or a spelling
    ///   correction passes nothing, because each of those is a decision of its own.
    func remember(_ label: String, coalescingKey: String? = nil) {
        if let key = coalescingKey, let last = undoStack.last,
           last.coalescingKey == key, Date().timeIntervalSince(last.madeAt) < 2 {
            return
        }

        undoStack.append(
            Snapshot(label: label, segments: segments, coalescingKey: coalescingKey, madeAt: Date())
        )
        if undoStack.count > Self.undoDepth { undoStack.removeFirst() }
        undoLabel = label
    }

    func undo() {
        guard let snapshot = undoStack.popLast() else { return }
        segments = snapshot.segments
        undoLabel = undoStack.last?.label

        // Whatever was selected may no longer exist, and the caption under the playhead
        // is worked out again on the next tick anyway.
        if let selectedSegmentID, !segments.contains(where: { $0.id == selectedSegmentID }) {
            self.selectedSegmentID = nil
        }
        if let activeSegmentID, !segments.contains(where: { $0.id == activeSegmentID }) {
            self.activeSegmentID = nil
        }
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
        remember(String(localized: "Delete subtitle"))
        segments.removeAll { $0.id == segment.id }
        if selectedSegmentID == segment.id { selectedSegmentID = nil }
        if activeSegmentID == segment.id { activeSegmentID = nil }
    }

    /// Inserts a new subtitle at the playhead, fitted into whatever gap is available.
    @discardableResult
    func addSegment(at time: TimeInterval, duration: TimeInterval = 2, limit: TimeInterval) -> SubtitleSegment {
        remember(String(localized: "Add subtitle"))
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
        remember(String(localized: "Words on screen"))
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

    /// The project as it stands right now, including unsaved edits - what an export
    /// must be built from.
    func currentProject() -> SubtitleProject {
        var current = project
        current.subtitles = segments
        current.captionStyle = captionStyle
        return current
    }

    func saveNow() async {
        project.subtitles = segments
        project.captionStyle = captionStyle
        project.updatedAt = Date()
        await onSave(project)
    }
}

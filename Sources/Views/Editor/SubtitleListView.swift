import SwiftUI

/// The scrollable list of subtitles. Used on its own after transcription, and as the
/// bottom section of the editor later.
struct SubtitleListView: View {
    let segments: [SubtitleSegment]
    var activeSegmentID: SubtitleSegment.ID?
    /// A tap moves the playhead to this subtitle. Nothing else - jumping around the
    /// video is the common action, so it gets the cheap gesture.
    var onSelect: ((SubtitleSegment) -> Void)?
    /// A press and hold opens it for editing.
    var onEdit: ((SubtitleSegment) -> Void)?

    var body: some View {
        LazyVStack(spacing: 8) {
            ForEach(Array(segments.enumerated()), id: \.element.id) { index, segment in
                SubtitleRow(
                    index: index + 1,
                    segment: segment,
                    isActive: segment.id == activeSegmentID
                )
                .contentShape(Rectangle())
                .onTapGesture { onSelect?(segment) }
                .onLongPressGesture(minimumDuration: 0.35) { onEdit?(segment) }
                .accessibilityAddTraits(.isButton)
            }
        }
    }
}

#Preview {
    ScrollView {
        SubtitleListView(
            segments: SubtitleSegment.samples,
            activeSegmentID: SubtitleSegment.samples[1].id
        )
        .padding()
    }
    .appBackground()
    .preferredColorScheme(.dark)
}

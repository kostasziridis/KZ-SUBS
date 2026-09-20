import SwiftUI

/// The scrollable list of subtitles. Used on its own after transcription, and as the
/// bottom section of the editor later.
struct SubtitleListView: View {
    let segments: [SubtitleSegment]
    var activeSegmentID: SubtitleSegment.ID?
    var onSelect: ((SubtitleSegment) -> Void)?

    var body: some View {
        LazyVStack(spacing: 8) {
            ForEach(Array(segments.enumerated()), id: \.element.id) { index, segment in
                Button {
                    onSelect?(segment)
                } label: {
                    SubtitleRow(
                        index: index + 1,
                        segment: segment,
                        isActive: segment.id == activeSegmentID
                    )
                }
                .buttonStyle(.plain)
                .disabled(onSelect == nil)
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

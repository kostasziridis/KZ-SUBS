import SwiftUI

/// One subtitle in the list: its number, its timing, its words.
struct SubtitleRow: View {
    let index: Int
    let segment: SubtitleSegment
    var isActive: Bool = false
    /// Opens this subtitle for editing. Spelled out as a button because holding a row
    /// is not something anyone discovers on their own.
    var onEdit: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(index)")
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(isActive ? .white : AppTheme.tertiaryText)
                .frame(width: 22, alignment: .trailing)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text("\(TimecodeFormatter.precise(segment.startTime)) — \(TimecodeFormatter.precise(segment.endTime))")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(isActive ? AppTheme.accent : AppTheme.tertiaryText)

                    Spacer(minLength: 0)

                    // On the timecode line rather than beside the words, so it never
                    // takes width away from the subtitle itself.
                    if let onEdit {
                        Button(action: onEdit) {
                            Label("Edit", systemImage: "pencil")
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 9)
                                .padding(.vertical, 4)
                                .background { Capsule().fill(AppTheme.elevatedSurface) }
                                .overlay { Capsule().strokeBorder(AppTheme.hairline, lineWidth: 1) }
                        }
                        .buttonStyle(.plain)
                        .tint(AppTheme.accent)
                        .foregroundStyle(AppTheme.accent)
                    }
                }

                Text(segment.text)
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(12)
        .background {
            AppTheme.cardShape(AppTheme.tileRadius)
                .fill(isActive ? AppTheme.accent.opacity(0.16) : AppTheme.elevatedSurface)
        }
        .overlay {
            AppTheme.cardShape(AppTheme.tileRadius)
                .strokeBorder(isActive ? AppTheme.accent.opacity(0.5) : AppTheme.hairline, lineWidth: 1)
        }
    }
}

#if DEBUG
#Preview {
    VStack(spacing: 10) {
        SubtitleRow(index: 1, segment: SubtitleSegment.samples[0])
        SubtitleRow(index: 2, segment: SubtitleSegment.samples[1], isActive: true)
    }
    .padding()
    .appBackground()
    .preferredColorScheme(.dark)
}
#endif

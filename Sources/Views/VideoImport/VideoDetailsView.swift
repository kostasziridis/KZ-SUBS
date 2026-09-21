import SwiftUI

/// The facts about the selected video: name, length, size on screen, frame rate.
struct VideoDetailsView: View {
    let asset: VideoAsset
    let fileSizeText: String?

    var body: some View {
        GlassCard(radius: AppTheme.controlRadius, padding: 18) {
            VStack(alignment: .leading, spacing: 12) {
                Text(FileHelpers.displayName(for: asset.url))
                    .font(.headline)
                    .foregroundStyle(.white)
                    .lineLimit(2)

                FlowRow(spacing: 8) {
                    InfoPill(symbol: "clock", text: TimecodeFormatter.duration(asset.duration))
                    InfoPill(symbol: "rectangle.ratio.16.to.9", text: asset.resolutionDescription)
                    if let quality = asset.qualityLabel {
                        InfoPill(symbol: "sparkles", text: quality)
                    }
                    InfoPill(symbol: "speedometer", text: asset.frameRateDescription)
                    if let fileSizeText {
                        InfoPill(symbol: "internaldrive", text: fileSizeText)
                    }
                    if !asset.hasAudio {
                        InfoPill(symbol: "speaker.slash", text: String(localized: "No sound"))
                    }
                }
            }
        }
    }
}

/// A minimal wrapping row - the pills should flow onto a second line on narrow screens.
struct FlowRow: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if rowWidth > 0, rowWidth + spacing + size.width > maxWidth {
                totalHeight += rowHeight + spacing
                rowWidth = size.width
                rowHeight = size.height
            } else {
                rowWidth += rowWidth > 0 ? spacing + size.width : size.width
                rowHeight = max(rowHeight, size.height)
            }
        }
        totalHeight += rowHeight
        return CGSize(width: maxWidth == .infinity ? rowWidth : maxWidth, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

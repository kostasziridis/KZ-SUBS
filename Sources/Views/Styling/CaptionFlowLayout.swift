import SwiftUI

/// Lays words out in wrapping lines, so each word can be its own view.
///
/// Needed because a padded, rounded box behind the spoken word cannot come from an
/// attributed string - an attributed background takes no inset. Laying the words out
/// individually gives each one a real view to put a real background behind, while this
/// keeps the wrapping and centring that ordinary text would have done for free.
struct CaptionFlowLayout: Layout {

    var alignment: CaptionStyle.TextAlignment = .center
    var spacing: CGFloat = 6
    var lineSpacing: CGFloat = 6

    private struct Line {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func lines(sizes: [CGSize], maxWidth: CGFloat) -> [Line] {
        var result: [Line] = []
        var current = Line()

        for (index, size) in sizes.enumerated() {
            let added = current.indices.isEmpty ? size.width : spacing + size.width

            if !current.indices.isEmpty, current.width + added > maxWidth {
                result.append(current)
                current = Line(indices: [index], width: size.width, height: size.height)
            } else {
                current.indices.append(index)
                current.width += added
                current.height = max(current.height, size.height)
            }
        }

        if !current.indices.isEmpty { result.append(current) }
        return result
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let maxWidth = proposal.width ?? sizes.reduce(0) { $0 + $1.width }
        let laid = lines(sizes: sizes, maxWidth: maxWidth)

        let height = laid.reduce(0) { $0 + $1.height }
            + CGFloat(max(0, laid.count - 1)) * lineSpacing
        let width = laid.map(\.width).max() ?? 0

        return CGSize(width: min(width, maxWidth), height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let laid = lines(sizes: sizes, maxWidth: bounds.width)

        var y = bounds.minY
        for line in laid {
            var x: CGFloat
            switch alignment {
            case .leading: x = bounds.minX
            case .trailing: x = bounds.maxX - line.width
            case .center: x = bounds.minX + (bounds.width - line.width) / 2
            }

            for index in line.indices {
                let size = sizes[index]
                subviews[index].place(
                    at: CGPoint(x: x, y: y + (line.height - size.height) / 2),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(size)
                )
                x += size.width + spacing
            }

            y += line.height + lineSpacing
        }
    }
}

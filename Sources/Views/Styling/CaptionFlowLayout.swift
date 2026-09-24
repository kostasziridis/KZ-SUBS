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

    /// The width the words are wrapped at.
    ///
    /// Read from the proposal in both passes, never from the bounds we are finally
    /// given. The two have to agree: measuring at one width and placing at another is
    /// how a caption reported the height of a single line and then drew two, the
    /// second cut off by the edge of the rendered image. The bounds come back a
    /// fraction narrower than the width we asked for - a rounding of a size this very
    /// method returned - and that fraction is enough to push the last word onto a line
    /// the height never allowed for.
    private func wrapWidth(_ proposal: ProposedViewSize, sizes: [CGSize], bounds: CGFloat?) -> CGFloat {
        if let width = proposal.width { return width }
        // No width proposed: placing follows the space we were actually given, and
        // measuring has nothing to go on but the words themselves.
        return bounds ?? sizes.reduce(0) { $0 + $1.width }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let laid = lines(sizes: sizes, maxWidth: wrapWidth(proposal, sizes: sizes, bounds: nil))

        let height = laid.reduce(0) { $0 + $1.height }
            + CGFloat(max(0, laid.count - 1)) * lineSpacing
        // Rounded up, so a parent that works in whole pixels cannot hand back less
        // room than the lines were measured in and change where they break.
        let width = (laid.map(\.width).max() ?? 0).rounded(.up)

        // Not clamped to the proposal. A word wider than the line cannot be broken, so
        // it is placed at its full width whatever this says - and reporting less than
        // was drawn is how it ended up cut off at the edges of the video.
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let laid = lines(sizes: sizes, maxWidth: wrapWidth(proposal, sizes: sizes, bounds: bounds.width))

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

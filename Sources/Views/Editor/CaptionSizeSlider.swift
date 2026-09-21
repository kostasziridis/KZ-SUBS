import SwiftUI

/// A vertical slider for caption size, sitting beside the video.
///
/// Pinching works, but it is awkward once the caption is small - the thing you need
/// to grab is the thing that has shrunk. This stays the same size whatever the
/// caption does.
struct CaptionSizeSlider: View {

    @Binding var value: Double
    var range: ClosedRange<Double>

    @State private var isDragging = false

    private var fraction: Double {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 0 }
        return min(max((value - range.lowerBound) / span, 0), 1)
    }

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "textformat.size.larger")
                .font(.caption2)
                .foregroundStyle(AppTheme.tertiaryText)

            GeometryReader { proxy in
                ZStack(alignment: .bottom) {
                    // Holds the track's width open now that the material is behind the
                    // stack rather than drawn as its first layer.
                    Capsule().fill(.clear)

                    Capsule()
                        .fill(AppTheme.accent)
                        .frame(height: max(6, proxy.size.height * fraction))
                }
                .floatingGlass(in: Capsule())
                .overlay(alignment: .bottom) {
                    Circle()
                        .fill(.white)
                        .frame(width: 18, height: 18)
                        .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
                        .offset(y: -(proxy.size.height - 18) * fraction)
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { drag in
                            isDragging = true
                            // Up is bigger, which is the way the control reads.
                            let position = 1 - (drag.location.y / max(proxy.size.height, 1))
                            let clamped = min(max(position, 0), 1)
                            value = range.lowerBound + clamped * (range.upperBound - range.lowerBound)
                        }
                        .onEnded { _ in isDragging = false }
                )
            }
            .frame(width: 26)

            Image(systemName: "textformat.size.smaller")
                .font(.caption2)
                .foregroundStyle(AppTheme.tertiaryText)
        }
        .scaleEffect(isDragging ? 1.06 : 1)
        .animation(.snappy(duration: 0.15), value: isDragging)
    }
}

#if DEBUG
#Preview {
    CaptionSizeSlider(value: .constant(60), range: 24...140)
        .frame(height: 200)
        .padding()
        .appBackground()
        .preferredColorScheme(.dark)
}
#endif

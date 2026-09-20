import SwiftUI

/// The KZ-SUBS mark, drawn rather than shipped as an image.
///
/// Redrawn from the source artwork's own coordinates, so it stays sharp at any size,
/// carries no background, and - the reason it matters here - each piece can be
/// animated on its own.
struct KZSubsMark: View {

    /// 0...1 across the whole reveal, so the pieces can be staggered.
    var progress: Double = 1

    /// The artwork's own coordinate space, kept so the proportions are exact.
    private let designOrigin = CGPoint(x: 325, y: 225)
    private let designSize = CGSize(width: 950, height: 755)

    private static let bubbleColors: [Color] = [
        Color(red: 0.098, green: 0.655, blue: 1.0),   // #19A7FF
        Color(red: 0.141, green: 0.420, blue: 1.0),   // #246BFF
        Color(red: 0.424, green: 0.169, blue: 1.0)    // #6C2BFF
    ]

    var body: some View {
        Canvas { context, size in
            let scale = min(size.width / designSize.width, size.height / designSize.height)
            let offsetX = (size.width - designSize.width * scale) / 2
            let offsetY = (size.height - designSize.height * scale) / 2

            func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                CGPoint(
                    x: (x - designOrigin.x) * scale + offsetX,
                    y: (y - designOrigin.y) * scale + offsetY
                )
            }
            func length(_ value: CGFloat) -> CGFloat { value * scale }

            let gradient = GraphicsContext.Shading.linearGradient(
                Gradient(stops: [
                    .init(color: Self.bubbleColors[0], location: 0),
                    .init(color: Self.bubbleColors[1], location: 0.52),
                    .init(color: Self.bubbleColors[2], location: 1)
                ]),
                startPoint: point(325, 225),
                endPoint: point(1275, 980)
            )

            // Bubble and its tail, drawn as one shape so the gradient runs through both.
            var bubble = Path(
                roundedRect: CGRect(origin: point(325, 225), size: CGSize(width: length(950), height: length(650))),
                cornerRadius: length(145),
                style: .continuous
            )

            var tail = Path()
            tail.move(to: point(525, 860))
            tail.addLine(to: point(525, 955))
            tail.addQuadCurve(to: point(548, 964), control: point(525, 980))
            tail.addLine(to: point(690, 860))
            tail.closeSubpath()
            bubble.addPath(tail)

            context.fill(bubble, with: gradient)

            // Play button.
            let playOpacity = stage(from: 0.15, to: 0.5)
            if playOpacity > 0 {
                var play = Path()
                play.move(to: point(670, 365))
                play.addQuadCurve(to: point(620, 364), control: point(646, 349))
                play.addQuadCurve(to: point(595, 410), control: point(595, 379))
                play.addLine(to: point(595, 605))
                play.addQuadCurve(to: point(620, 651), control: point(595, 636))
                play.addQuadCurve(to: point(670, 650), control: point(646, 666))
                play.addLine(to: point(860, 532))
                play.addQuadCurve(to: point(885, 493), control: point(885, 516))
                play.addQuadCurve(to: point(860, 454), control: point(885, 470))
                play.closeSubpath()

                context.opacity = playOpacity
                context.fill(play, with: .color(.white))
                context.opacity = 1
            }

            // Subtitle lines, revealed left to right - the app's whole idea in one gesture.
            drawSubtitleLine(
                context: context,
                rect: CGRect(origin: point(470, 690), size: CGSize(width: length(660), height: length(38))),
                radius: length(19),
                reveal: stage(from: 0.35, to: 0.7)
            )
            drawSubtitleLine(
                context: context,
                rect: CGRect(origin: point(470, 772), size: CGSize(width: length(460), height: length(38))),
                radius: length(19),
                reveal: stage(from: 0.5, to: 0.85)
            )
        }
        .aspectRatio(designSize.width / designSize.height, contentMode: .fit)
    }

    private func drawSubtitleLine(context: GraphicsContext, rect: CGRect, radius: CGFloat, reveal: Double) {
        guard reveal > 0 else { return }
        let visible = CGRect(
            origin: rect.origin,
            size: CGSize(width: rect.width * reveal, height: rect.height)
        )
        context.fill(
            Path(roundedRect: visible, cornerRadius: min(radius, visible.width / 2), style: .continuous),
            with: .color(.white)
        )
    }

    /// Maps overall progress onto one piece's own 0...1 window.
    private func stage(from start: Double, to end: Double) -> Double {
        guard end > start else { return progress >= end ? 1 : 0 }
        return min(max((progress - start) / (end - start), 0), 1)
    }
}

/// "KZ SUBS", set to match the artwork: Arial Bold, KZ in the brand gradient.
struct KZSubsWordmark: View {
    var size: CGFloat = 44

    private static let kzGradient = LinearGradient(
        colors: [
            Color(red: 0.039, green: 0.549, blue: 1.0),  // #0A8CFF
            Color(red: 0.141, green: 0.282, blue: 1.0)   // #2448FF
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    var body: some View {
        HStack(spacing: size * 0.22) {
            Text("KZ").foregroundStyle(Self.kzGradient)
            Text("SUBS").foregroundStyle(.white)
        }
        // Arial ships with iOS, so this matches the artwork rather than approximating it.
        .font(.custom("Arial-BoldMT", size: size))
        .tracking(-size * 0.04)
    }
}

#if DEBUG
#Preview {
    VStack(spacing: 30) {
        KZSubsMark().frame(width: 220)
        KZSubsWordmark(size: 46)
    }
    .padding(40)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .appBackground()
    .preferredColorScheme(.dark)
}
#endif

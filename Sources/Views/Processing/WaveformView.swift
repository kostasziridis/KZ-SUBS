import SwiftUI

/// A gently breathing bar meter shown while the engine listens.
///
/// Decorative, not a real signal reading. Driven by one repeating animation with
/// staggered delays rather than per-frame state, so it costs nothing while the
/// Neural Engine is busy.
struct WaveformView: View {
    var barCount: Int = 27
    var isAnimating: Bool = true

    @State private var raised = false

    var body: some View {
        HStack(alignment: .center, spacing: 4) {
            ForEach(0..<barCount, id: \.self) { index in
                Capsule()
                    .fill(AppTheme.accent.opacity(0.85))
                    .frame(width: 4, height: barHeight(at: index))
                    .animation(
                        isAnimating
                            ? .easeInOut(duration: 0.55)
                                .repeatForever(autoreverses: true)
                                .delay(Double(index) * 0.045)
                            : .default,
                        value: raised
                    )
            }
        }
        .frame(height: 64)
        .onAppear { raised = isAnimating }
        .onChange(of: isAnimating) { _, newValue in raised = newValue }
    }

    /// A fixed profile so the meter looks like a waveform rather than noise.
    private func barHeight(at index: Int) -> CGFloat {
        let profile: [CGFloat] = [0.3, 0.55, 0.85, 0.45, 0.7, 1.0, 0.4, 0.65, 0.9]
        let base = profile[index % profile.count]
        let low = 10 + base * 8
        let high = 12 + base * 50
        return raised ? high : low
    }
}

#Preview {
    WaveformView()
        .padding()
        .appBackground()
        .preferredColorScheme(.dark)
}

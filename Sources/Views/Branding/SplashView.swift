import SwiftUI

/// The opening moment: the mark draws itself, the name arrives, then the site.
///
/// Short on purpose. A launch animation earns a second of someone's attention, not
/// more, so it can be tapped away and it gets out of the way by itself.
struct SplashView: View {

    var onFinished: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var markProgress: Double = 0
    @State private var markScale: CGFloat = 0.86
    @State private var showsWordmark = false
    @State private var showsSite = false
    @State private var isLeaving = false
    @State private var hasFinished = false

    var body: some View {
        ZStack {
            AppTheme.background.ignoresSafeArea()

            // A faint wash behind the mark, so the dark screen is not flat.
            RadialGradient(
                colors: [Color(red: 0.11, green: 0.24, blue: 0.55).opacity(0.55), .clear],
                center: .center,
                startRadius: 0,
                endRadius: 420
            )
            .ignoresSafeArea()
            .opacity(markProgress)

            VStack(spacing: 30) {
                KZSubsMark(progress: markProgress)
                    .frame(width: 210)
                    .scaleEffect(markScale)

                VStack(spacing: 14) {
                    KZSubsWordmark(size: 40)
                        .opacity(showsWordmark ? 1 : 0)
                        .offset(y: showsWordmark ? 0 : 14)

                    Text("kziridis.com")
                        .font(.footnote.weight(.medium))
                        .tracking(1.6)
                        .foregroundStyle(AppTheme.secondaryText)
                        .opacity(showsSite ? 1 : 0)
                        .offset(y: showsSite ? 0 : 8)
                }
            }
            .opacity(isLeaving ? 0 : 1)
            .scaleEffect(isLeaving ? 1.04 : 1)
        }
        .contentShape(Rectangle())
        // Nobody should be held hostage by a splash screen.
        .onTapGesture { finish() }
        .task { await run() }
    }

    private func run() async {
        if reduceMotion {
            markProgress = 1
            markScale = 1
            showsWordmark = true
            showsSite = true
            try? await Task.sleep(for: .milliseconds(900))
            finish()
            return
        }

        withAnimation(.easeOut(duration: 1.05)) { markProgress = 1 }
        withAnimation(.spring(response: 0.75, dampingFraction: 0.72)) { markScale = 1 }

        try? await Task.sleep(for: .milliseconds(620))
        guard !hasFinished else { return }
        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) { showsWordmark = true }

        try? await Task.sleep(for: .milliseconds(340))
        guard !hasFinished else { return }
        withAnimation(.easeOut(duration: 0.45)) { showsSite = true }

        try? await Task.sleep(for: .milliseconds(820))
        guard !hasFinished else { return }
        finish()
    }

    private func finish() {
        guard !hasFinished else { return }
        hasFinished = true
        withAnimation(.easeIn(duration: 0.32)) { isLeaving = true }

        Task {
            try? await Task.sleep(for: .milliseconds(320))
            onFinished()
        }
    }
}

#Preview {
    SplashView { }
        .preferredColorScheme(.dark)
}

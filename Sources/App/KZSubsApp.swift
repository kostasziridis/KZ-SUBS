import AVFoundation
import SwiftUI

@main
struct KZSubsApp: App {

    @State private var appState = AppState()
    @State private var router = AppRouter()
    @State private var showsSplash = true

    init() {
        configureAudioSession()
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                // Home is built underneath, so its projects are loaded and ready by the
                // time the splash steps aside.
                HomeView()
                    .environment(appState)
                    .environment(router)
                    .task {
                        await appState.bootstrap()
                    }

                if showsSplash {
                    SplashView {
                        withAnimation(.easeOut(duration: 0.3)) { showsSplash = false }
                    }
                    .transition(.opacity)
                    .zIndex(1)
                }
            }
            .preferredColorScheme(.dark)
            .tint(AppTheme.accent)
        }
    }

    /// Video sound should play even when the ring switch is silenced, the way every
    /// video app behaves.
    private func configureAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        } catch {
            AppLog.app.error("Audio session setup failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}

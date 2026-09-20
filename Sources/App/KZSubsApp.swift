import AVFoundation
import SwiftUI

@main
struct KZSubsApp: App {

    @State private var appState = AppState()
    @State private var router = AppRouter()

    init() {
        configureAudioSession()
    }

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environment(appState)
                .environment(router)
                .preferredColorScheme(.dark)
                .tint(AppTheme.accent)
                .task {
                    await appState.bootstrap()
                }
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

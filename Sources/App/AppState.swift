import Foundation
import Observation

/// App-wide state: the project library, plus one-time startup work.
@MainActor
@Observable
final class AppState {
    private(set) var projects: [SubtitleProject] = []
    private(set) var isLoadingProjects = true

    private let store = ProjectStore.shared

    /// Prepares storage off the main thread, then loads the saved projects.
    func bootstrap() async {
        await Task.detached(priority: .utility) {
            StorageManager.prepare()
        }.value

        projects = await store.load()
        isLoadingProjects = false
        AppLog.app.info("Loaded \(self.projects.count, privacy: .public) project(s)")
    }

    func save(_ project: SubtitleProject) async {
        var updated = project
        updated.updatedAt = Date()
        projects = await store.upsert(updated, into: projects)
    }

    func delete(_ project: SubtitleProject) async {
        projects = await store.delete(project, from: projects)
    }

    #if DEBUG
    /// Preview-only seam: fills the library without touching disk.
    func applyPreviewProjects(_ projects: [SubtitleProject]) {
        self.projects = projects
        self.isLoadingProjects = false
    }
    #endif
}

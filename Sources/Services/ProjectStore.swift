import Foundation

/// Reads and writes the project list. An actor so disk work never lands on the main thread
/// and two saves can never interleave.
actor ProjectStore {
    static let shared = ProjectStore()

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    /// Projects whose video file still exists, newest first.
    func load() -> [SubtitleProject] {
        let url = StorageManager.projectsFileURL
        guard let data = try? Data(contentsOf: url) else { return [] }

        do {
            let projects = try decoder.decode([SubtitleProject].self, from: data)
            return projects
                .filter { FileManager.default.fileExists(atPath: $0.videoURL.path) }
                .sorted { $0.updatedAt > $1.updatedAt }
        } catch {
            AppLog.storage.error("Project list unreadable: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    func save(_ projects: [SubtitleProject]) {
        StorageManager.ensureDirectoryExists(StorageManager.projectsFileURL.deletingLastPathComponent())
        do {
            let data = try encoder.encode(projects)
            try data.write(to: StorageManager.projectsFileURL, options: .atomic)
        } catch {
            AppLog.storage.error("Saving projects failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Inserts or replaces a project and persists the whole list.
    func upsert(_ project: SubtitleProject, into projects: [SubtitleProject]) -> [SubtitleProject] {
        var updated = projects
        if let index = updated.firstIndex(where: { $0.id == project.id }) {
            updated[index] = project
        } else {
            updated.insert(project, at: 0)
        }
        updated.sort { $0.updatedAt > $1.updatedAt }
        save(updated)
        return updated
    }

    func delete(_ project: SubtitleProject, from projects: [SubtitleProject]) -> [SubtitleProject] {
        let remaining = projects.filter { $0.id != project.id }
        StorageManager.removeFiles(for: project)
        save(remaining)
        return remaining
    }
}

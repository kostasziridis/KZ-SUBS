import Foundation

/// Owns every file the app creates: imported videos, thumbnails, working audio and exports.
///
/// Nothing here ever touches the user's original media in Photos - imports are copies.
enum StorageManager {

    // MARK: - Locations

    private static var containerDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("KZSubs", isDirectory: true)
    }

    /// Imported source videos. Long-lived: a project is useless without its video.
    static var videosDirectory: URL {
        containerDirectory.appendingPathComponent("Videos", isDirectory: true)
    }

    /// Project thumbnails. Cheap to regenerate, but kept alongside projects.
    static var thumbnailsDirectory: URL {
        containerDirectory.appendingPathComponent("Thumbnails", isDirectory: true)
    }

    /// Scratch space for extracted audio and in-flight exports. Safe to wipe at launch.
    static var workingDirectory: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("KZSubsWork", isDirectory: true)
    }

    static var projectsFileURL: URL {
        containerDirectory.appendingPathComponent("projects.json", isDirectory: false)
    }

    // MARK: - Lifecycle

    /// Creates the directory tree and clears leftover scratch files.
    /// Call once, early, off the main thread.
    static func prepare() {
        for directory in [videosDirectory, thumbnailsDirectory, workingDirectory] {
            ensureDirectoryExists(directory)
        }
        var videos = videosDirectory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? videos.setResourceValues(values)

        clearWorkingDirectory()
    }

    static func ensureDirectoryExists(_ url: URL) {
        guard !FileManager.default.fileExists(atPath: url.path) else { return }
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    static func clearWorkingDirectory() {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(at: workingDirectory, includingPropertiesForKeys: nil) else { return }
        for url in contents {
            try? fm.removeItem(at: url)
        }
    }

    // MARK: - Importing

    /// Copies a picked video into app-controlled storage under a collision-free name.
    /// - Throws: `AppError.notEnoughStorage` when the copy would not fit.
    static func stageImportedVideo(from source: URL) throws -> URL {
        ensureDirectoryExists(videosDirectory)

        let incomingSize = fileSize(of: source)
        if let incomingSize, !hasRoom(for: incomingSize) {
            throw AppError.notEnoughStorage
        }

        let destination = uniqueURL(
            in: videosDirectory,
            preferredName: source.lastPathComponent,
            fallbackExtension: "mov"
        )

        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }

        try FileManager.default.copyItem(at: source, to: destination)
        return destination
    }

    // MARK: - Space

    /// Bytes the system considers available for important user data.
    static var availableCapacity: Int64? {
        let values = try? containerDirectory.resourceValues(
            forKeys: [.volumeAvailableCapacityForImportantUsageKey]
        )
        return values?.volumeAvailableCapacityForImportantUsage
    }

    /// Leaves a margin so we never fill the disk to the last byte.
    static func hasRoom(for bytes: Int64, margin: Int64 = 250_000_000) -> Bool {
        guard let available = availableCapacity else { return true }
        return available > bytes + margin
    }

    static func fileSize(of url: URL) -> Int64? {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
        guard let size = values?.fileSize else { return nil }
        return Int64(size)
    }

    /// Total bytes used by everything the app stores.
    static func usedBytes() -> Int64 {
        [videosDirectory, thumbnailsDirectory, workingDirectory]
            .reduce(0) { $0 + directorySize(of: $1) }
    }

    static func directorySize(of directory: URL) -> Int64 {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey]
        ) else { return 0 }

        var total: Int64 = 0
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            guard values?.isRegularFile == true, let size = values?.fileSize else { continue }
            total += Int64(size)
        }
        return total
    }

    // MARK: - Removal

    /// Removes the files backing a project. Never call this on a user's original media.
    static func removeFiles(for project: SubtitleProject) {
        let fm = FileManager.default
        if project.videoURL.path.hasPrefix(videosDirectory.path) {
            try? fm.removeItem(at: project.videoURL)
        }
        if let thumb = project.thumbnailURL, thumb.path.hasPrefix(thumbnailsDirectory.path) {
            try? fm.removeItem(at: thumb)
        }
    }

    // MARK: - Naming

    static func uniqueURL(in directory: URL, preferredName: String, fallbackExtension: String) -> URL {
        let sanitized = preferredName
            .replacingOccurrences(of: "/", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        var base = (sanitized as NSString).deletingPathExtension
        var ext = (sanitized as NSString).pathExtension
        if base.isEmpty { base = "Video" }
        if ext.isEmpty { ext = fallbackExtension }

        var candidate = directory.appendingPathComponent("\(base).\(ext)")
        var counter = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(base)-\(counter).\(ext)")
            counter += 1
        }
        return candidate
    }
}

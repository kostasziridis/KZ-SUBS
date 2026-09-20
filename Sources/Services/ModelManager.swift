import Foundation
import WhisperKit

/// Chooses which speech model to use, downloads it once, and remembers where it went.
///
/// Kept apart from `WhisperService` so the model policy can change without touching
/// transcription code.
enum ModelManager {

    /// What the user asked for: speed, balance, or the best accuracy available.
    ///
    /// Every option is multilingual - Greek is a requirement, so English-only builds
    /// are never candidates whatever the choice.
    enum Choice: String, CaseIterable, Identifiable, Sendable {
        case fast, balanced, accurate

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .fast: return "Fast"
            case .balanced: return "Balanced"
            case .accurate: return "Most accurate"
            }
        }

        var detail: String {
            switch self {
            case .fast: return "Quickest, and easiest on battery. Less reliable with accents and background noise."
            case .balanced: return "The recommended choice. Near the accuracy of the large model at a fraction of the time."
            case .accurate: return "The most accurate model. Noticeably slower, and a larger download."
            }
        }

        var approximateSize: String {
            switch self {
            case .fast: return "~250 MB"
            case .balanced: return "~630 MB"
            case .accurate: return "~950 MB"
            }
        }

        /// Roughly how long the one-time setup takes, download plus first preparation.
        var estimatedSetupTime: String {
            switch self {
            case .fast: return "about 1-2 minutes"
            case .balanced: return "about 3-5 minutes"
            case .accurate: return "about 5-8 minutes"
            }
        }

        /// Candidates for this choice, best first.
        var variants: [String] {
            switch self {
            case .fast:
                return ["openai_whisper-small", "openai_whisper-base"]
            case .balanced:
                return [
                    "openai_whisper-large-v3-v20240930_turbo_632MB",
                    "openai_whisper-large-v3_turbo_954MB",
                    "openai_whisper-small"
                ]
            case .accurate:
                return [
                    "openai_whisper-large-v3_947MB",
                    "openai_whisper-large-v3-v20240930_626MB",
                    "openai_whisper-large-v3-v20240930_turbo_632MB"
                ]
            }
        }
    }

    private static let choiceKey = "speechModelChoice"

    /// The user's pick, defaulting to balanced.
    static var choice: Choice {
        get {
            guard let raw = UserDefaults.standard.string(forKey: choiceKey) else { return .balanced }
            return Choice(rawValue: raw) ?? .balanced
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: choiceKey) }
    }

    /// True once this variant has been downloaded and is still on disk.
    static func isDownloaded(_ variant: String) -> Bool {
        cachedFolder(for: variant) != nil
    }

    /// Whether a model for this choice is already on the device.
    ///
    /// Checked without the network, because the point is to decide whether to warn the
    /// user about a download before anything starts.
    static func isReady(for choice: Choice = ModelManager.choice) -> Bool {
        choice.variants.contains { isDownloaded($0) }
    }

    /// Variants we would pick when the user has expressed no preference, best first.
    ///
    /// Every entry is multilingual: Greek is a hard requirement, so English-only builds
    /// are not candidates. The large-v3 turbo build leads because it is the strongest
    /// multilingual option that still runs comfortably on the Neural Engine.
    static let preferredVariants: [String] = [
        "openai_whisper-large-v3-v20240930_turbo_632MB",
        "openai_whisper-large-v3_turbo_954MB",
        "openai_whisper-large-v3_947MB",
        "openai_whisper-small",
        "openai_whisper-base",
    ]

    /// Whisper ships English-only builds in two disguises: a `.en` suffix, and the whole
    /// distil-whisper family. Both are useless here.
    static func isMultilingual(_ variant: String) -> Bool {
        !variant.contains(".en") && !variant.lowercased().contains("distil")
    }

    /// Picks the best multilingual variant this device supports, honouring the choice.
    static func selectVariant(from support: ModelSupport, choice: Choice = ModelManager.choice) -> String {
        let supported = support.supported.filter { isMultilingual($0) && !support.disabled.contains($0) }

        // What the user asked for comes first, as long as the device supports it.
        if let wanted = choice.variants.first(where: { supported.contains($0) }) {
            return wanted
        }
        if let preferred = preferredVariants.first(where: { supported.contains($0) }) {
            return preferred
        }
        if isMultilingual(support.default) {
            return support.default
        }
        return supported.first ?? "openai_whisper-base"
    }

    /// Asks WhisperKit what this device supports, preferring the live list and falling
    /// back to the bundled one when there is no network.
    static func resolveVariant() async -> String {
        let remote = await WhisperKit.recommendedRemoteModels(downloadBase: StorageManager.modelsDirectory)
        if !remote.supported.isEmpty {
            return selectVariant(from: remote)
        }
        return selectVariant(from: WhisperKit.recommendedModels())
    }

    // MARK: - Local cache

    private static func defaultsKey(for variant: String) -> String { "modelFolder.\(variant)" }

    /// The folder a previous download left behind, if it is still there.
    ///
    /// A remembered path is only a hint. iOS hands an app a new container path after
    /// some installs and restores, so a path recorded earlier can point nowhere while
    /// the model itself is sitting in the new container - and believing it would mean
    /// downloading hundreds of megabytes that are already on the device. When the hint
    /// misses, the model is searched for instead.
    static func cachedFolder(for variant: String) -> URL? {
        if let remembered = rememberedFolder(for: variant) { return remembered }

        if let found = locateDownloadedFolder(for: variant) {
            rememberFolder(found, for: variant)
            return found
        }

        UserDefaults.standard.removeObject(forKey: defaultsKey(for: variant))
        return nil
    }

    private static func rememberedFolder(for variant: String) -> URL? {
        guard let stored = UserDefaults.standard.string(forKey: defaultsKey(for: variant)) else { return nil }

        // Stored relative to the models directory, so it survives a container move.
        let url = stored.hasPrefix("/")
            ? URL(fileURLWithPath: stored)
            : StorageManager.modelsDirectory.appendingPathComponent(stored)

        return isUsableModelFolder(url) ? url : nil
    }

    /// Searches the models directory for a complete copy of this variant.
    static func locateDownloadedFolder(for variant: String) -> URL? {
        let fileManager = FileManager.default
        guard let walker = fileManager.enumerator(
            at: StorageManager.modelsDirectory,
            includingPropertiesForKeys: [.isDirectoryKey]
        ) else { return nil }

        for case let url as URL in walker where url.lastPathComponent == variant {
            if isUsableModelFolder(url) { return url }
        }
        return nil
    }

    /// A folder only counts when the model files are actually in it. A download that
    /// stopped half way leaves the directory behind, and loading that crashes deep
    /// inside Core ML rather than failing cleanly.
    private static func isUsableModelFolder(_ url: URL) -> Bool {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return false
        }

        return ["MelSpectrogram.mlmodelc", "AudioEncoder.mlmodelc", "TextDecoder.mlmodelc"].allSatisfy {
            fileManager.fileExists(atPath: url.appendingPathComponent($0).path)
        }
    }

    static func rememberFolder(_ url: URL, for variant: String) {
        let base = StorageManager.modelsDirectory.path
        let path = url.path
        let relative = path.hasPrefix(base)
            ? String(path.dropFirst(base.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            : path

        UserDefaults.standard.set(relative, forKey: defaultsKey(for: variant))
    }

    /// Downloads the variant unless it is already on disk.
    /// - Parameter onProgress: fraction complete, 0...1.
    static func ensureAvailable(
        variant: String,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws -> URL {
        if let cached = cachedFolder(for: variant) {
            return cached
        }

        StorageManager.ensureDirectoryExists(StorageManager.modelsDirectory)

        do {
            let folder = try await WhisperKit.download(
                variant: variant,
                downloadBase: StorageManager.modelsDirectory,
                useBackgroundSession: false,
                progressCallback: { progress in
                    onProgress(progress.fractionCompleted)
                }
            )
            rememberFolder(folder, for: variant)
            return folder
        } catch {
            AppLog.speech.error("Model download failed: \(error.localizedDescription, privacy: .public)")
            throw AppError.unableToPrepareModel
        }
    }
}

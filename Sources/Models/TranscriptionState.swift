import Foundation

/// Every stage the subtitle generation pipeline can be in.
/// Views render straight from this - they never infer progress from side effects.
enum TranscriptionState {
    case idle
    /// `progress` is `nil` while the download size is still unknown.
    case preparingModel(progress: Double?)
    case preparingAudio
    case transcribing(progress: Double)
    case completed
    case cancelled
    case failed(Error)

    var isBusy: Bool {
        switch self {
        case .preparingModel, .preparingAudio, .transcribing: return true
        case .idle, .completed, .cancelled, .failed: return false
        }
    }
}

/// The export pipeline's equivalent.
enum ExportState {
    case idle
    case preparing
    case rendering(progress: Double)
    case savingToPhotos
    case completed(URL)
    case cancelled
    case failed(Error)

    var isBusy: Bool {
        switch self {
        case .preparing, .rendering, .savingToPhotos: return true
        case .idle, .completed, .cancelled, .failed: return false
        }
    }
}

import Foundation
import Observation
import PhotosUI
import SwiftUI

/// Drives the home screen: picking a video, importing it, surfacing failures.
@MainActor
@Observable
final class HomeViewModel {

    /// Bound to `PhotosPicker`.
    var pickerItem: PhotosPickerItem?

    /// Non-nil once an import succeeds; the navigation stack pushes on it.
    var importedAsset: VideoAsset?

    private(set) var isImporting = false
    var error: AppError?

    /// One import at a time - a second tap while copying a 4K clip must not start another.
    @ObservationIgnored private var importTask: Task<Void, Never>?

    func handlePickerSelection(_ item: PhotosPickerItem?) {
        guard let item, importTask == nil else { return }

        isImporting = true
        importTask = Task { [weak self] in
            guard let self else { return }
            defer {
                self.isImporting = false
                self.importTask = nil
                self.pickerItem = nil
            }

            do {
                let asset = try await VideoImporter.importVideo(from: item)
                guard !Task.isCancelled else { return }

                // A missing audio track is not an error here: the import screen shows
                // the video and states plainly why subtitles cannot work.
                self.importedAsset = asset
            } catch let error as AppError {
                self.error = error
            } catch {
                AppLog.media.error("Import failed: \(error.localizedDescription, privacy: .public)")
                self.error = .unableToLoadVideo
            }
        }
    }

    func cancelImport() {
        importTask?.cancel()
        importTask = nil
        isImporting = false
    }
}

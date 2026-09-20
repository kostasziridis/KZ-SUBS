import Foundation
import Observation
import Photos

/// Drives the export screen: burning in the video, writing the SRT, saving to Photos.
@MainActor
@Observable
final class ExportViewModel {

    let project: SubtitleProject

    private(set) var state: ExportState = .idle
    private(set) var exportedVideoURL: URL?
    private(set) var subtitleFileURL: URL?
    /// True when the export had to draw one caption per subtitle instead of per word.
    private(set) var simplifiedHighlighting = false
    private(set) var savedToPhotos = false

    var error: AppError?

    /// One export at a time; a second tap must not start a parallel render.
    @ObservationIgnored private var job: Task<Void, Never>?

    init(project: SubtitleProject) {
        self.project = project
    }

    var isWorking: Bool { state.isBusy }

    var progress: Double? {
        if case let .rendering(value) = state { return value }
        return nil
    }

    var resolutionText: String {
        "\(Int(project.pixelSize.width.rounded())) × \(Int(project.pixelSize.height.rounded()))"
    }

    // MARK: - Video

    func exportVideo() {
        guard job == nil else { return }
        guard !project.subtitles.isEmpty else {
            error = .exportFailed
            return
        }

        savedToPhotos = false
        state = .preparing

        job = Task { [weak self] in
            guard let self else { return }
            defer { self.job = nil }

            do {
                let result = try await VideoExporter.shared.export(project: self.project) { [weak self] fraction in
                    Task { @MainActor in
                        self?.state = .rendering(progress: fraction)
                    }
                }

                try Task.checkCancellation()
                self.exportedVideoURL = result.url
                self.simplifiedHighlighting = result.simplifiedHighlighting
                self.state = .completed(result.url)
            } catch is CancellationError {
                self.state = .cancelled
            } catch let error as AppError {
                self.error = error
                self.state = .failed(error)
            } catch {
                self.error = .exportFailed
                self.state = .failed(error)
            }
        }
    }

    func cancel() {
        job?.cancel()
    }

    // MARK: - Subtitles file

    func exportSubtitleFile() {
        do {
            subtitleFileURL = try SRTExporter.write(project.subtitles, name: project.name)
        } catch let error as AppError {
            self.error = error
        } catch {
            self.error = .exportFailed
        }
    }

    // MARK: - Photos

    /// Saves the finished video to the photo library.
    ///
    /// Asks only for permission to add, never to read: the app has no business
    /// browsing someone's library.
    func saveToPhotos() async {
        guard let url = exportedVideoURL else { return }

        let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        let granted: PHAuthorizationStatus
        if status == .notDetermined {
            granted = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        } else {
            granted = status
        }

        guard granted == .authorized || granted == .limited else {
            error = .photosAccessUnavailable
            return
        }

        state = .savingToPhotos
        do {
            try await PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: .video, fileURL: url, options: nil)
            }
            savedToPhotos = true
            state = .completed(url)
        } catch {
            AppLog.media.error("Saving to Photos failed: \(error.localizedDescription, privacy: .public)")
            self.error = .exportFailed
            state = .completed(url)
        }
    }
}

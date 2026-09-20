import AVFoundation
import CoreTransferable
import Foundation
import PhotosUI
import UniformTypeIdentifiers

/// A movie handed over by the photo picker, already copied into our own storage.
///
/// The picker's file is temporary and disappears when the transfer closure returns,
/// so the copy has to happen inside it.
struct ImportedMovie: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .movie) { received in
            let copy = try StorageManager.stageImportedVideo(from: received.file)
            return ImportedMovie(url: copy)
        }
    }
}

/// Turns a picked item into a `VideoAsset` with real, orientation-correct metadata.
enum VideoImporter {

    static func importVideo(from item: PhotosPickerItem) async throws -> VideoAsset {
        let movie: ImportedMovie?
        do {
            movie = try await item.loadTransferable(type: ImportedMovie.self)
        } catch let error as AppError {
            throw error
        } catch {
            AppLog.media.error("Picker transfer failed: \(error.localizedDescription, privacy: .public)")
            throw AppError.unableToLoadVideo
        }

        guard let movie else { throw AppError.unableToLoadVideo }
        return try await makeAsset(for: movie.url)
    }

    /// Reads duration, display size, frame rate and audio presence from a local file.
    static func makeAsset(for url: URL) async throws -> VideoAsset {
        let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])

        do {
            let duration = try await asset.load(.duration)
            let seconds = duration.isNumeric ? duration.seconds : 0

            guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
                throw AppError.unableToLoadVideo
            }

            let (naturalSize, transform, nominalFrameRate) = try await videoTrack.load(
                .naturalSize, .preferredTransform, .nominalFrameRate
            )

            // Applying the transform is what makes portrait video report portrait dimensions.
            let transformed = naturalSize.applying(transform)
            let displaySize = CGSize(width: abs(transformed.width), height: abs(transformed.height))

            let audioTracks = try await asset.loadTracks(withMediaType: .audio)
            let hasAudio = !audioTracks.isEmpty

            let thumbnailURL = await ThumbnailGenerator.makeThumbnail(for: url, duration: seconds)

            return VideoAsset(
                url: url,
                filename: url.lastPathComponent,
                duration: seconds,
                pixelSize: displaySize,
                frameRate: Double(nominalFrameRate),
                hasAudio: hasAudio,
                thumbnailURL: thumbnailURL
            )
        } catch let error as AppError {
            throw error
        } catch {
            AppLog.media.error("Asset inspection failed: \(error.localizedDescription, privacy: .public)")
            throw AppError.unableToLoadVideo
        }
    }
}

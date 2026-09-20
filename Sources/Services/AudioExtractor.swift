import AVFoundation
import Foundation

/// Pulls the soundtrack out of a video and writes it as audio the speech engine can
/// read directly.
///
/// Streams through `AVAssetReader`/`AVAssetWriter` rather than loading the movie:
/// a 4K clip's video track is never touched, and audio moves through in small buffers,
/// so memory stays flat regardless of length.
enum AudioExtractor {

    /// What the speech engine wants: 16 kHz, mono, 16-bit PCM. Writing exactly this
    /// means the audio is converted once here rather than again inside the engine.
    static let sampleRate: Double = 16_000

    static var pcmSettings: [String: Any] {
        [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]
    }

    /// Extracts the audio track to a WAV file in the working directory.
    ///
    /// - Parameter onProgress: 0...1, based on how far through the timeline we are.
    /// - Returns: URL of the written file. The caller owns it and should delete it when done.
    /// - Throws: `AppError.videoHasNoAudio` when there is no soundtrack,
    ///           `CancellationError` if the task is cancelled.
    static func extractAudio(
        from videoURL: URL,
        onProgress: @escaping @Sendable (Double) -> Void = { _ in }
    ) async throws -> URL {

        let asset = AVURLAsset(url: videoURL, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])

        guard let audioTrack = try await asset.loadTracks(withMediaType: .audio).first else {
            throw AppError.videoHasNoAudio
        }

        let duration = try await asset.load(.duration)
        let totalSeconds = duration.isNumeric ? duration.seconds : 0

        guard StorageManager.hasRoom(for: estimatedSize(seconds: totalSeconds)) else {
            throw AppError.notEnoughStorage
        }

        StorageManager.ensureDirectoryExists(StorageManager.workingDirectory)
        let outputURL = StorageManager.workingDirectory
            .appendingPathComponent("\(UUID().uuidString).wav")
        // A leftover file at the destination makes AVAssetWriter fail outright.
        try? FileManager.default.removeItem(at: outputURL)

        let extraction = try PCMExtraction(
            asset: asset,
            audioTrack: audioTrack,
            outputURL: outputURL,
            totalSeconds: totalSeconds,
            onProgress: onProgress
        )

        do {
            try await extraction.run()
            onProgress(1)
            AppLog.media.info("Extracted audio to \(outputURL.lastPathComponent, privacy: .public)")
            return outputURL
        } catch {
            try? FileManager.default.removeItem(at: outputURL)
            throw error
        }
    }

    /// 16 kHz mono 16-bit is 32 KB per second, plus a little slack for the header.
    private static func estimatedSize(seconds: Double) -> Int64 {
        Int64(max(0, seconds) * sampleRate * 2) + 100_000
    }

    /// Removes an extracted file once it is no longer needed.
    static func discard(_ url: URL) {
        guard url.path.hasPrefix(StorageManager.workingDirectory.path) else { return }
        try? FileManager.default.removeItem(at: url)
    }
}

/// One reader/writer pair, driving a single extraction.
///
/// `@unchecked Sendable` is deliberate and narrow: AVFoundation is not `Sendable`, but
/// every call below happens on `queue` - the one serial queue AVFoundation calls back
/// on - so these objects are never touched from two places at once.
private final class PCMExtraction: @unchecked Sendable {

    private let reader: AVAssetReader
    private let writer: AVAssetWriter
    private let writerInput: AVAssetWriterInput
    private let readerOutput: AVAssetReaderAudioMixOutput
    private let totalSeconds: Double
    private let onProgress: @Sendable (Double) -> Void
    private let queue = DispatchQueue(label: "gr.kziridis.kzsubs.audio-extract")

    init(
        asset: AVAsset,
        audioTrack: AVAssetTrack,
        outputURL: URL,
        totalSeconds: Double,
        onProgress: @escaping @Sendable (Double) -> Void
    ) throws {
        self.totalSeconds = totalSeconds
        self.onProgress = onProgress

        reader = try AVAssetReader(asset: asset)
        writer = try AVAssetWriter(outputURL: outputURL, fileType: .wav)

        // A mix output downmixes multi-channel audio for us, so stereo and surround
        // both arrive as the mono the engine expects.
        readerOutput = AVAssetReaderAudioMixOutput(
            audioTracks: [audioTrack],
            audioSettings: AudioExtractor.pcmSettings
        )
        readerOutput.alwaysCopiesSampleData = false

        writerInput = AVAssetWriterInput(mediaType: .audio, outputSettings: AudioExtractor.pcmSettings)
        writerInput.expectsMediaDataInRealTime = false

        guard reader.canAdd(readerOutput), writer.canAdd(writerInput) else {
            throw AppError.unableToGenerateSubtitles
        }
        reader.add(readerOutput)
        writer.add(writerInput)
    }

    func run() async throws {
        guard reader.startReading() else { throw reader.error ?? AppError.unableToGenerateSubtitles }
        guard writer.startWriting() else { throw writer.error ?? AppError.unableToGenerateSubtitles }
        writer.startSession(atSourceTime: .zero)

        do {
            try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    writerInput.requestMediaDataWhenReady(on: queue) { [self] in
                        pump(continuation)
                    }
                }
            } onCancel: { [self] in
                reader.cancelReading()
            }
        } catch {
            writer.cancelWriting()
            throw error
        }

        await writer.finishWriting()

        guard writer.status == .completed else {
            throw writer.error ?? AppError.unableToGenerateSubtitles
        }
    }

    /// Moves buffers while the writer accepts them. Resumes the continuation exactly
    /// once, on the first outcome reached.
    private func pump(_ continuation: CheckedContinuation<Void, Error>) {
        while writerInput.isReadyForMoreMediaData {
            if Task.isCancelled {
                reader.cancelReading()
                writerInput.markAsFinished()
                continuation.resume(throwing: CancellationError())
                return
            }

            guard let buffer = readerOutput.copyNextSampleBuffer() else {
                // No more data: either finished cleanly or the read failed.
                writerInput.markAsFinished()
                if reader.status == .failed {
                    continuation.resume(throwing: reader.error ?? AppError.unableToGenerateSubtitles)
                } else {
                    continuation.resume()
                }
                return
            }

            guard writerInput.append(buffer) else {
                reader.cancelReading()
                writerInput.markAsFinished()
                continuation.resume(throwing: writer.error ?? AppError.unableToGenerateSubtitles)
                return
            }

            if totalSeconds > 0 {
                let time = CMSampleBufferGetPresentationTimeStamp(buffer).seconds
                if time.isFinite {
                    onProgress(min(1, max(0, time / totalSeconds)))
                }
            }
        }
    }
}

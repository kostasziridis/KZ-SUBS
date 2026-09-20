import AVFoundation
import Foundation
import Observation

/// Owns a single `AVPlayer` for the lifetime of a screen.
///
/// SwiftUI rebuilds view structs constantly; the player must not be rebuilt with them,
/// so it lives here and the view only reads state.
@MainActor
@Observable
final class VideoPlayerViewModel {

    // MARK: - Published state

    private(set) var isPlaying = false
    private(set) var currentTime: TimeInterval = 0
    private(set) var duration: TimeInterval = 0
    private(set) var isReady = false

    /// Set while the user drags the scrubber, so the time observer stops fighting them.
    var isScrubbing = false {
        didSet { if isScrubbing { pause() } }
    }

    // MARK: - Internals

    @ObservationIgnored let player = AVPlayer()
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var statusObservation: NSKeyValueObservation?
    @ObservationIgnored private var rateObservation: NSKeyValueObservation?
    @ObservationIgnored private var endObserver: NSObjectProtocol?
    @ObservationIgnored private var loadedURL: URL?
    /// How often playback time is published. 10/s is plenty for a scrubber; word-by-word
    /// highlighting needs finer steps, so the editor raises it. Set before `load`.
    @ObservationIgnored var observationInterval: TimeInterval = 0.1
    @ObservationIgnored private var isSeekInFlight = false
    @ObservationIgnored private var pendingSeek: (time: TimeInterval, precise: Bool)?

    // MARK: - Lifecycle

    /// Loads a video. Calling it again with the same URL is a no-op, which is what
    /// makes it safe to call from `.task` on every appearance.
    func load(url: URL, knownDuration: TimeInterval? = nil) {
        guard loadedURL != url else { return }
        loadedURL = url

        removeObservers()

        let item = AVPlayerItem(url: url)
        player.replaceCurrentItem(with: item)
        player.actionAtItemEnd = .pause

        duration = knownDuration ?? 0
        currentTime = 0
        isReady = false

        addObservers(for: item)
    }

    /// Releases the player's work. Call from `onDisappear`.
    func teardown() {
        pause()
        removeObservers()
        player.replaceCurrentItem(with: nil)
        loadedURL = nil
        isReady = false
        currentTime = 0
    }

    deinit {
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
        }
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
    }

    // MARK: - Transport

    func play() {
        guard isReady else { return }
        // Restart from the top when the user hits play at the very end.
        if duration > 0, currentTime >= duration - 0.05 {
            seek(to: 0, precise: true)
        }
        player.play()
    }

    func pause() {
        player.pause()
    }

    func togglePlayback() {
        isPlaying ? pause() : play()
    }

    /// - Parameter precise: exact seeking for editing; loose seeking stays smooth while dragging.
    func seek(to time: TimeInterval, precise: Bool = false) {
        let clamped = min(max(0, time), max(duration, 0))
        currentTime = clamped

        // Dragging a scrubber produces seeks faster than the player can service them.
        // Keep only the most recent one instead of queuing every intermediate position.
        guard !isSeekInFlight else {
            pendingSeek = (clamped, precise)
            return
        }
        performSeek(to: clamped, precise: precise)
    }

    private func performSeek(to time: TimeInterval, precise: Bool) {
        isSeekInFlight = true
        let target = CMTime(seconds: time, preferredTimescale: 600)
        let tolerance = precise ? CMTime.zero : CMTime(seconds: 0.1, preferredTimescale: 600)

        player.seek(to: target, toleranceBefore: tolerance, toleranceAfter: tolerance) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isSeekInFlight = false
                if let pending = self.pendingSeek {
                    self.pendingSeek = nil
                    self.performSeek(to: pending.time, precise: pending.precise)
                }
            }
        }
    }

    func skip(by seconds: TimeInterval) {
        seek(to: currentTime + seconds, precise: true)
    }

    // MARK: - Observation

    private func addObservers(for item: AVPlayerItem) {
        let interval = CMTime(seconds: observationInterval, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self, !self.isScrubbing else { return }
                self.currentTime = time.seconds.isFinite ? time.seconds : 0
            }
        }

        statusObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch item.status {
                case .readyToPlay:
                    let itemDuration = item.duration.seconds
                    if itemDuration.isFinite, itemDuration > 0 {
                        self.duration = itemDuration
                    }
                    self.isReady = true
                case .failed:
                    AppLog.player.error("Player item failed: \(item.error?.localizedDescription ?? "unknown", privacy: .public)")
                    self.isReady = false
                default:
                    break
                }
            }
        }

        rateObservation = player.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] player, _ in
            Task { @MainActor [weak self] in
                self?.isPlaying = player.timeControlStatus == .playing
            }
        }

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.currentTime = self.duration
            }
        }
    }

    private func removeObservers() {
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
        statusObservation?.invalidate()
        statusObservation = nil
        rateObservation?.invalidate()
        rateObservation = nil
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
    }
}

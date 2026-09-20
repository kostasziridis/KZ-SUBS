import Foundation

/// Every time string in the app comes from here, so timecodes never drift in style.
enum TimecodeFormatter {

    /// `mm:ss`, growing to `h:mm:ss` only when the video is long enough to need it.
    static func duration(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds).rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }

    /// `mm:ss` with a fixed two-digit minute field, for player readouts that must not jitter.
    static func playhead(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%02d:%02d", minutes, secs)
    }

    /// `mm:ss.SS` - the precision subtitle timing needs.
    static func precise(_ seconds: TimeInterval) -> String {
        let clamped = max(0, seconds)
        let total = Int(clamped)
        let minutes = total / 60
        let secs = total % 60
        let hundredths = Int((clamped - Double(total)) * 100)
        return String(format: "%02d:%02d.%02d", minutes, secs, hundredths)
    }

    /// `HH:MM:SS,mmm` - the SRT wire format, comma separator included.
    static func srt(_ seconds: TimeInterval) -> String {
        let clamped = max(0, seconds)
        let totalMilliseconds = Int((clamped * 1000).rounded())
        let hours = totalMilliseconds / 3_600_000
        let minutes = (totalMilliseconds % 3_600_000) / 60_000
        let secs = (totalMilliseconds % 60_000) / 1000
        let millis = totalMilliseconds % 1000
        return String(format: "%02d:%02d:%02d,%03d", hours, minutes, secs, millis)
    }

    /// "Edited 2 hours ago"
    static func relative(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

import OSLog

/// Developer-facing logging. User-facing copy never comes from here.
enum AppLog {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "gr.agrotechniki.kzsubs"

    static let app = Logger(subsystem: subsystem, category: "app")
    static let media = Logger(subsystem: subsystem, category: "media")
    static let player = Logger(subsystem: subsystem, category: "player")
    static let storage = Logger(subsystem: subsystem, category: "storage")
    static let speech = Logger(subsystem: subsystem, category: "speech")
}

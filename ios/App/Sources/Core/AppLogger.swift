import Foundation
import OSLog

/// Log categories used across the app. One `os.Logger` per category.
enum LogCategory: String, CaseIterable, Sendable {
    case app, data, sync, score, coach, purchase
}

/// Thin wrapper around `os.Logger`.
///
/// Messages are redacted (`.private`) by default so user data never lands in
/// sysdiagnose in the clear; pass `.public` only for non-sensitive text.
struct AppLogger: Sendable {
    enum Privacy: Sendable { case `private`, `public` }

    static let subsystem = Bundle.main.bundleIdentifier ?? "com.barishizm.gymanalyzer"

    let category: LogCategory
    private let logger: Logger

    init(_ category: LogCategory) {
        self.category = category
        self.logger = Logger(subsystem: Self.subsystem, category: category.rawValue)
    }

    func debug(_ message: @autoclosure () -> String, privacy: Privacy = .private) {
        let text = message()
        switch privacy {
        case .private: logger.debug("\(text, privacy: .private)")
        case .public: logger.debug("\(text, privacy: .public)")
        }
    }

    func info(_ message: @autoclosure () -> String, privacy: Privacy = .private) {
        let text = message()
        switch privacy {
        case .private: logger.info("\(text, privacy: .private)")
        case .public: logger.info("\(text, privacy: .public)")
        }
    }

    func error(_ message: @autoclosure () -> String, privacy: Privacy = .private) {
        let text = message()
        switch privacy {
        case .private: logger.error("\(text, privacy: .private)")
        case .public: logger.error("\(text, privacy: .public)")
        }
    }
}

/// Shared loggers: `Log.app.info("…")`.
enum Log {
    static let app = AppLogger(.app)
    static let data = AppLogger(.data)
    static let sync = AppLogger(.sync)
    static let score = AppLogger(.score)
    static let coach = AppLogger(.coach)
    static let purchase = AppLogger(.purchase)

    static func logger(for category: LogCategory) -> AppLogger {
        switch category {
        case .app: app
        case .data: data
        case .sync: sync
        case .score: score
        case .coach: coach
        case .purchase: purchase
        }
    }
}

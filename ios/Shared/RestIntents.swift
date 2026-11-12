import AppIntents
import Foundation

/// A button press on the Live Activity, forwarded to the app's rest timer.
enum RestCommand: Sendable, Equatable {
    case skip
    case adjust(seconds: Int)
}

/// Bridge between the Live Activity intents and the rest timer. The app installs `handler` at launch; a
/// `LiveActivityIntent` runs in the app's process, so the handler is there when the button is tapped.
@MainActor
final class RestCommandCenter {
    static let shared = RestCommandCenter()

    var handler: (@MainActor (RestCommand) async -> Void)?

    func send(_ command: RestCommand) async {
        await handler?(command)
    }
}

/// "Skip rest" button.
struct SkipRestIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "liveactivity.intent.skip"
    static let isDiscoverable = false

    init() {}

    func perform() async throws -> some IntentResult {
        await RestCommandCenter.shared.send(.skip)
        return .result()
    }
}

/// "+15 s" button.
struct ExtendRestIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "liveactivity.intent.extend"
    static let isDiscoverable = false

    init() {}

    func perform() async throws -> some IntentResult {
        await RestCommandCenter.shared.send(.adjust(seconds: 15))
        return .result()
    }
}

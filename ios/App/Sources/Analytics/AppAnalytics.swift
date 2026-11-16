import DataKit
import Foundation
import OSLog
import TelemetryDeck

/// `UserDefaults` backing for the analytics opt-out switch and milestone ledger.
struct UserDefaultsAnalyticsStorage: AnalyticsStorage {
    private let defaults: SendableDefaults

    init(defaults: UserDefaults) { self.defaults = SendableDefaults(defaults) }

    func bool(forKey key: String) -> Bool? { defaults.object(forKey: key) as? Bool }
    func set(_ value: Bool, forKey key: String) { defaults.set(value, forKey: key) }
    func date(forKey key: String) -> Date? { defaults.object(forKey: key) as? Date }
    func set(_ value: Date, forKey key: String) { defaults.set(value, forKey: key) }
}

/// Sends events to TelemetryDeck. Only the closed `AnalyticsEvent` vocabulary reaches it (no free text, no numbers).
struct TelemetryDeckAnalytics: Analytics {
    func send(_ event: AnalyticsEvent) {
        TelemetryDeck.signal(event.name, parameters: event.parameters)
    }
}

/// The app's single analytics entry point. With no `TelemetryDeckAppID` configured (local builds, tests) events go nowhere.
enum AppAnalytics {
    static let shared: AnalyticsService = {
        let sink: any Analytics
        let appID = (Bundle.main.object(forInfoDictionaryKey: "TelemetryDeckAppID") as? String) ?? ""
        if appID.isEmpty || appID.hasPrefix("$(") || ProcessInfo.processInfo.arguments.contains(where: { $0.hasPrefix("-uitest") }) {
            sink = NoopAnalytics()
        } else {
            TelemetryDeck.initialize(config: .init(appID: appID))
            sink = TelemetryDeckAnalytics()
        }
        return AnalyticsService(sink: sink, storage: UserDefaultsAnalyticsStorage(defaults: .standard))
    }()
}

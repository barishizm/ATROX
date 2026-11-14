import Foundation

/// Sink for anonymous product events. The app uses the TelemetryDeck implementation; tests use `RecordingAnalytics`.
public protocol Analytics: Sendable {
    func send(_ event: AnalyticsEvent)
}

public struct NoopAnalytics: Analytics {
    public init() {}
    public func send(_ event: AnalyticsEvent) {}
}

/// Test double that remembers what was sent.
public final class RecordingAnalytics: Analytics, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [AnalyticsEvent] = []
    public init() {}
    public var events: [AnalyticsEvent] { lock.withLock { storage } }
    public func send(_ event: AnalyticsEvent) { lock.withLock { storage.append(event) } }
}

/// Key-value storage for the milestone ledger and the opt-out (UserDefaults in the app, a dictionary in tests).
public protocol AnalyticsStorage: Sendable {
    func bool(forKey key: String) -> Bool?
    func set(_ value: Bool, forKey key: String)
    func date(forKey key: String) -> Date?
    func set(_ value: Date, forKey key: String)
}

public final class InMemoryAnalyticsStorage: AnalyticsStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Any] = [:]
    public init() {}
    public func bool(forKey key: String) -> Bool? { lock.withLock { values[key] as? Bool } }
    public func set(_ value: Bool, forKey key: String) { lock.withLock { values[key] = value } }
    public func date(forKey key: String) -> Date? { lock.withLock { values[key] as? Date } }
    public func set(_ value: Date, forKey key: String) { lock.withLock { values[key] = value } }
}

/// Wraps a sink with the user's opt-out switch, once-per-install milestones and the day-7 return check.
public final class AnalyticsService: Analytics, @unchecked Sendable {
    public static let enabledKey = "analytics.enabled"
    private static let firstLaunchKey = "analytics.firstLaunch"
    private static func sentKey(_ event: AnalyticsEvent) -> String { "analytics.sent.\(event.name)" }

    private let sink: any Analytics
    private let storage: any AnalyticsStorage
    private let clock: @Sendable () -> Date
    private let lock = NSLock()

    public init(sink: any Analytics, storage: any AnalyticsStorage, clock: @escaping @Sendable () -> Date = { Date() }) {
        self.sink = sink
        self.storage = storage
        self.clock = clock
    }

    /// On by default: events are anonymous. Settings can switch it off.
    public var isEnabled: Bool {
        get { storage.bool(forKey: Self.enabledKey) ?? true }
        set { storage.set(newValue, forKey: Self.enabledKey) }
    }

    public func send(_ event: AnalyticsEvent) {
        guard isEnabled else { return }
        if event.isOncePerInstall {
            let shouldSend = lock.withLock { () -> Bool in
                let key = Self.sentKey(event)
                if storage.bool(forKey: key) == true { return false }
                storage.set(true, forKey: key)
                return true
            }
            guard shouldSend else { return }
        }
        sink.send(event)
    }

    /// Call on every launch: records the first launch and reports the day-7 return once, on the first launch 7+ days later.
    public func appLaunched() {
        guard isEnabled else { return }
        guard let first = storage.date(forKey: Self.firstLaunchKey) else {
            storage.set(clock(), forKey: Self.firstLaunchKey)
            return
        }
        if clock().timeIntervalSince(first) >= 7 * 86_400 { send(.day7Return) }
    }
}

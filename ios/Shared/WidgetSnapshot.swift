import Foundation

/// What the home-screen widgets, Lock Screen widgets and Shortcuts read (P096). The app writes one small JSON
/// document into the shared app group whenever the Today numbers change; the widget extension only ever reads it
/// (the extension does not link DataKit). Compiled into the app and the extension.
struct WidgetSnapshot: Codable, Equatable, Sendable {
    static let currentVersion = 1

    struct Score: Codable, Equatable, Sendable {
        var value: Int
        /// Too little data for a trustworthy overall score yet (shown with a "provisional" label).
        var isProvisional: Bool
        /// Points gained or lost over the last 30 days; nil when there is nothing to compare with.
        var change: Int?
    }

    struct PlannedDay: Codable, Equatable, Sendable, Identifiable {
        var routineId: UUID
        var dayId: UUID
        var routineName: String
        var dayName: String
        var exerciseCount: Int
        var id: UUID { dayId }
    }

    var version: Int = WidgetSnapshot.currentVersion
    var generatedAt: Date
    var score: Score?
    /// The next workout (what the "Today's workout" widget starts); nil without an active program.
    var next: PlannedDay?
    /// Every day of the active program, for the "program day" parameter of Start workout.
    var days: [PlannedDay] = []
    var weeklyDone: Int
    var weeklyGoal: Int
    var streakWeeks: Int
    var trainedToday: Bool
    /// When the week behind `weeklyDone` ends; after that the count shown is 0 even if the app did not run again.
    var weekEndsAt: Date

    /// Workouts counted in the week that contains `now`.
    func weeklyDone(at now: Date) -> Int { now < weekEndsAt ? weeklyDone : 0 }

    /// 0...1 progress of the weekly goal ring.
    func weeklyProgress(at now: Date) -> Double {
        guard weeklyGoal > 0 else { return 0 }
        return min(Double(weeklyDone(at: now)) / Double(weeklyGoal), 1)
    }

    /// Equal apart from the time it was written (so an unchanged state does not reload the widgets).
    func hasSameContent(as other: WidgetSnapshot) -> Bool {
        var copy = self
        copy.generatedAt = other.generatedAt
        return copy == other
    }

    func day(id: UUID) -> PlannedDay? { days.first { $0.dayId == id } ?? (next?.dayId == id ? next : nil) }
}

/// Reads and writes the snapshot in the app group's `UserDefaults`.
struct WidgetSnapshotStore: @unchecked Sendable {
    static let key = "widget.snapshot.v1"

    private let defaults: UserDefaults

    init(defaults: UserDefaults) { self.defaults = defaults }

    /// The store in the shared app group (`AppGroupID` in Info.plist); nil when the group is not available.
    static func appGroup(id: String? = Bundle.main.infoDictionary?["AppGroupID"] as? String) -> WidgetSnapshotStore? {
        guard let id, !id.isEmpty, !id.hasPrefix("$("), let defaults = UserDefaults(suiteName: id) else { return nil }
        return WidgetSnapshotStore(defaults: defaults)
    }

    func read() -> WidgetSnapshot? {
        guard let data = defaults.data(forKey: Self.key),
              let snapshot = try? JSONDecoder.snapshot.decode(WidgetSnapshot.self, from: data),
              snapshot.version == WidgetSnapshot.currentVersion else { return nil }
        return snapshot
    }

    /// True when the stored value changed (callers reload the widget timelines only then).
    @discardableResult
    func write(_ snapshot: WidgetSnapshot) -> Bool {
        guard let data = try? JSONEncoder.snapshot.encode(snapshot) else { return false }
        if let old = read(), old.hasSameContent(as: snapshot) { return false }
        defaults.set(data, forKey: Self.key)
        return true
    }

    /// Sign-out: the widgets go back to their "sign in" placeholder.
    func clear() { defaults.removeObject(forKey: Self.key) }
}

private extension JSONEncoder {
    static var snapshot: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}

private extension JSONDecoder {
    static var snapshot: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }
}

/// When a widget shows what, and when it asks WidgetKit to read the snapshot again.
enum WidgetTimelinePlan {
    /// The app reloads timelines itself when a workout ends; this is the fallback that keeps a widget from going
    /// stale on a day the app is not opened ("a few times a day").
    static let refreshInterval: TimeInterval = 6 * 3600

    /// Entry dates (the first is `now`; one more at the week rollover so the weekly count resets on time) and the
    /// date WidgetKit should call the provider again.
    static func plan(for snapshot: WidgetSnapshot?, now: Date) -> (entryDates: [Date], reloadAfter: Date) {
        var dates = [now]
        let reload = now.addingTimeInterval(refreshInterval)
        if let end = snapshot?.weekEndsAt, end > now, end <= reload { dates.append(end) }
        return (dates, reload)
    }
}

/// What a widget family renders for a given snapshot.
enum WidgetContentState: Equatable {
    /// The app has never written a snapshot: not signed in, or the app has not been opened since the install.
    case signedOut
    /// Signed in, but no overall score yet.
    case noScore
    case ready

    init(_ snapshot: WidgetSnapshot?) {
        guard let snapshot else { self = .signedOut; return }
        self = snapshot.score == nil ? .noScore : .ready
    }
}

/// `atrox://` links the widgets and controls open; `DeepLink` in the app target parses the same shapes.
enum WidgetLink {
    static func scheme(info: [String: Any]? = Bundle.main.infoDictionary) -> String {
        let value = (info?["AppURLScheme"] as? String)?.lowercased()
        return (value?.isEmpty == false && value?.hasPrefix("$(") == false) ? value! : "atrox"
    }

    static func tab(_ name: String, scheme: String = scheme()) -> URL { URL(string: "\(scheme)://\(name)")! }

    static func startWorkout(_ day: WidgetSnapshot.PlannedDay, scheme: String = scheme()) -> URL {
        URL(string: "\(scheme)://start/\(day.routineId.uuidString)/\(day.dayId.uuidString)")!
    }
}

/// Weigh-ins entered through Shortcuts or Siri.
enum WeightEntry {
    static let range: ClosedRange<Double> = 20...500

    /// The weight in kilograms rounded to 0.1, or nil when it is not a plausible body weight.
    static func kilograms(_ value: Double) -> Double? {
        guard value.isFinite, range.contains(value) else { return nil }
        return (value * 10).rounded() / 10
    }
}

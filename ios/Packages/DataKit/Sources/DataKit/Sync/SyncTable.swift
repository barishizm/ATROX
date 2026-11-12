import Foundation

/// The synced server tables (docs/02-MIMARI.md §2.4), **in dependency order**: a row is pushed only after the tables
/// it references, and `allCases` is that order. Consents are append-only and synced later (see ILERLEME).
public enum SyncTable: String, Sendable, CaseIterable, Codable {
    case profiles
    case userSettings = "user_settings"
    case bodyMeasurements = "body_measurements"
    case customExercises = "custom_exercises"
    case routines
    case routineDays = "routine_days"
    case routineExercises = "routine_exercises"
    case workouts
    case workoutExercises = "workout_exercises"
    case sets
    case personalRecords = "personal_records"

    /// Foreign keys inside the user's own data (column → referenced table). The fake server enforces them and the
    /// engine relies on `allCases` order to satisfy them.
    public var references: [String: SyncTable] {
        switch self {
        case .profiles, .userSettings, .bodyMeasurements, .customExercises, .routines: [:]
        case .routineDays: ["routine_id": .routines]
        case .routineExercises: ["routine_day_id": .routineDays, "custom_exercise_id": .customExercises]
        case .workouts: ["routine_id": .routines, "routine_day_id": .routineDays]
        case .workoutExercises: ["workout_id": .workouts, "custom_exercise_id": .customExercises]
        case .sets: ["workout_exercise_id": .workoutExercises]
        case .personalRecords: ["set_id": .sets, "custom_exercise_id": .customExercises]
        }
    }

    /// Rows that belong to a workout's tree and therefore follow its sync lock while it is active.
    var isWorkoutTree: Bool { self == .workouts || self == .workoutExercises || self == .sets }
}

/// Wire formats of time values. Timestamps go out in UTC with microseconds; the server may answer with any number of
/// fraction digits and a `+00:00` offset. `date` columns are calendar days in the device's time zone.
public enum SyncTime {
    public static func timestamp(_ date: Date) -> String {
        let total = date.timeIntervalSince1970
        var seconds = total.rounded(.down)
        var micros = Int(((total - seconds) * 1_000_000).rounded())
        if micros >= 1_000_000 {
            seconds += 1
            micros -= 1_000_000
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: Date(timeIntervalSince1970: seconds))
        return String(
            format: "%04d-%02d-%02dT%02d:%02d:%02d.%06dZ",
            parts.year ?? 0, parts.month ?? 0, parts.day ?? 0, parts.hour ?? 0, parts.minute ?? 0, parts.second ?? 0, micros
        )
    }

    public static func parseTimestamp(_ text: String) -> Date? {
        var base = text
        var fraction = 0.0
        if let dot = text.firstIndex(of: ".") {
            let digits = text[text.index(after: dot)...].prefix { $0.isNumber }
            fraction = Double("0." + digits) ?? 0
            base = String(text[..<dot]) + text[text.index(dot, offsetBy: digits.count + 1)...]
        }
        if base.hasSuffix("+00") { base += ":00" }
        base = base.replacingOccurrences(of: " ", with: "T")
        guard let whole = try? Date(base, strategy: Date.ISO8601FormatStyle(timeZone: .gmt)) else { return nil }
        return whole.addingTimeInterval(fraction)
    }

    public static func day(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    public static func parseDay(_ text: String, calendar: Calendar = .current) -> Date? {
        let parts = text.prefix(10).split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12))
    }
}

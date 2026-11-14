import Foundation

/// One Monday-to-Sunday week in the user's calendar (P070). The week always starts on Monday so the summary closes on
/// Sunday evening whatever the region's first weekday is.
public struct WeekPeriod: Sendable, Equatable {
    /// Start of Monday (inclusive) and start of the next Monday (exclusive), in the calendar's time zone.
    public let start: Date
    public let end: Date
    /// First and last day number (`ScoreCalculator.dayNumber`) of the week.
    public let startDay: Int
    public let endDay: Int

    public static func mondayCalendar(_ calendar: Calendar) -> Calendar {
        var copy = calendar
        copy.firstWeekday = 2
        copy.minimumDaysInFirstWeek = 4
        return copy
    }

    public static func containing(_ date: Date, calendar: Calendar = .current) -> WeekPeriod {
        let cal = mondayCalendar(calendar)
        let start = cal.dateInterval(of: .weekOfYear, for: date)?.start ?? cal.startOfDay(for: date)
        let end = cal.date(byAdding: .weekOfYear, value: 1, to: start) ?? start.addingTimeInterval(7 * 86_400)
        let startDay = ScoreCalculator.dayNumber(start, calendar: cal)
        return WeekPeriod(start: start, end: end, startDay: startDay, endDay: startDay + 6)
    }

    public func shifted(weeks: Int, calendar: Calendar = .current) -> WeekPeriod {
        let cal = Self.mondayCalendar(calendar)
        return Self.containing(cal.date(byAdding: .weekOfYear, value: weeks, to: start) ?? start, calendar: cal)
    }

    public func contains(_ date: Date) -> Bool { date >= start && date < end }
}

/// A score that moved during the week.
public struct WeeklyScoreChange: Sendable, Equatable {
    public var key: String
    public var change: Double

    public init(key: String, change: Double) {
        self.key = key
        self.change = change
    }
}

/// What a week of training amounts to (P070). Built by `WeeklySummaryBuilder`; every field is already derived.
public struct WeeklySummary: Sendable, Equatable, Identifiable {
    public var period: WeekPeriod
    public var workouts: Int
    public var goal: Int
    public var totalSets: Int
    public var previousSets: Int
    /// Percent change of the sets against the week before; nil without a comparison.
    public var volumeChange: Double?
    public var records: [RecordHighlight]
    /// Overall score at the end of the week and how far it moved; both nil without snapshots.
    public var overallScore: Double?
    public var overallChange: Double?
    /// Exercise score moves, biggest first (at most three).
    public var exerciseChanges: [WeeklyScoreChange]
    public var topGroup: VolumeBucket?
    public var neglectedGroups: [VolumeBucket]

    public var id: Int { period.startDay }
    public init(
        period: WeekPeriod, workouts: Int, goal: Int, totalSets: Int, previousSets: Int, volumeChange: Double?,
        records: [RecordHighlight], overallScore: Double?, overallChange: Double?, exerciseChanges: [WeeklyScoreChange],
        topGroup: VolumeBucket?, neglectedGroups: [VolumeBucket]
    ) {
        self.period = period
        self.workouts = workouts
        self.goal = goal
        self.totalSets = totalSets
        self.previousSets = previousSets
        self.volumeChange = volumeChange
        self.records = records
        self.overallScore = overallScore
        self.overallChange = overallChange
        self.exerciseChanges = exerciseChanges
        self.topGroup = topGroup
        self.neglectedGroups = neglectedGroups
    }

    public var isEmpty: Bool { workouts == 0 }
    public var metGoal: Bool { workouts >= goal }
}

/// Everything the builder reads, already fetched.
public struct WeeklySummaryInput: Sendable {
    public var period: WeekPeriod
    /// Start times of the finished workouts (any week; the builder picks the week).
    public var workouts: [Date]
    /// Working sets per day and exercise covering this and the previous week.
    public var entries: [VolumeEntry]
    public var roles: [String: MuscleRoles]
    public var records: [RecordHighlight]
    public var goal: Int
    public var overall: [ScorePoint]
    public var exercises: [String: [ScorePoint]]

    public init(
        period: WeekPeriod, workouts: [Date], entries: [VolumeEntry], roles: [String: MuscleRoles], records: [RecordHighlight],
        goal: Int, overall: [ScorePoint], exercises: [String: [ScorePoint]]
    ) {
        self.period = period
        self.workouts = workouts
        self.entries = entries
        self.roles = roles
        self.records = records
        self.goal = goal
        self.overall = overall
        self.exercises = exercises
    }
}

public enum WeeklySummaryBuilder {
    /// Score moves smaller than this are noise (same bar as the score refresh).
    public static let meaningfulChange = 0.5
    public static let maxExerciseChanges = 3

    public static func build(_ input: WeeklySummaryInput, calendar: Calendar = .current) -> WeeklySummary {
        let period = input.period
        let windows = VolumeSeries.weekly(input.entries, roles: input.roles, endDay: period.endDay, weeks: 2, calendar: calendar)
        let current = windows.last
        let previous = windows.count == 2 ? windows[0] : nil
        let totalSets = current?.totalSets ?? 0
        let previousSets = previous?.totalSets ?? 0
        let buckets = current?.buckets ?? [:]
        let workouts = input.workouts.filter(period.contains).count
        let records = input.records.filter { period.contains($0.date) }.sorted { $0.date > $1.date }
        let overall = move(input.overall, in: period)
        var changes: [WeeklyScoreChange] = []
        for (key, points) in input.exercises {
            guard let moved = move(points, in: period), abs(moved.change) >= meaningfulChange else { continue }
            changes.append(WeeklyScoreChange(key: key, change: moved.change))
        }
        changes.sort { abs($0.change) != abs($1.change) ? abs($0.change) > abs($1.change) : $0.key < $1.key }
        let trained = totalSets > 0
        let topGroup = trained ? VolumeBucket.allCases.filter { (buckets[$0] ?? 0) > 0 }.max { (buckets[$0] ?? 0) < (buckets[$1] ?? 0) } : nil
        let neglected: [VolumeBucket] = trained ? VolumeBucket.allCases.filter { (buckets[$0] ?? 0) == 0 } : []
        let volumeChange: Double? = previousSets > 0 && trained ? Double(totalSets - previousSets) / Double(previousSets) * 100 : nil
        var overallChange: Double?
        if let change = overall?.change, abs(change) >= meaningfulChange { overallChange = change }
        return WeeklySummary(
            period: period, workouts: workouts, goal: max(1, input.goal), totalSets: totalSets, previousSets: previousSets,
            volumeChange: volumeChange, records: records, overallScore: overall?.end, overallChange: overallChange,
            exerciseChanges: Array(changes.prefix(maxExerciseChanges)), topGroup: topGroup, neglectedGroups: neglected
        )
    }

    /// Score at the end of the week and its change against the last point before the week; nil when either is missing.
    static func move(_ points: [ScorePoint], in period: WeekPeriod) -> (end: Double, change: Double)? {
        let sorted = points.sorted { $0.date < $1.date }
        guard let base = sorted.last(where: { $0.date < period.start }), let end = sorted.last(where: { $0.date < period.end }),
              end.date >= period.start else { return nil }
        return (end.score, end.score - base.score)
    }
}

/// When the weekly notification fires.
public enum WeeklySchedule {
    public static let defaultHour = 19

    /// The next Sunday at `hour:minute` strictly after `now`, in the calendar's time zone.
    public static func nextFire(after now: Date, hour: Int, minute: Int = 0, calendar: Calendar = .current) -> Date? {
        calendar.nextDate(
            after: now, matching: DateComponents(hour: hour, minute: minute, weekday: 1), matchingPolicy: .nextTime
        )
    }
}

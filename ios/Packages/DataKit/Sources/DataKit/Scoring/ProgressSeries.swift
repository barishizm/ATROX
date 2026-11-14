import Foundation
import StrengthKit

// Pure series preparation behind the progress charts of the Analysis tab (P068): time ranges, thinning for long
// histories, record markers, plateau zones, weekly volume buckets, the training calendar and relative strength.
// No storage, no UI.

// MARK: - Time range

/// The range selector of the progress charts (1M / 3M / 6M / 1Y / All).
public enum ChartRange: String, Sendable, CaseIterable, Identifiable {
    case month, quarter, halfYear, year, all

    public var id: String { rawValue }

    /// Days the range reaches back from today; nil = the whole history.
    public var days: Int? {
        switch self {
        case .month: 30
        case .quarter: 91
        case .halfYear: 182
        case .year: 365
        case .all: nil
        }
    }

    /// First day number inside the range (nil = unbounded).
    public func startDay(today: Int) -> Int? { days.map { today - $0 } }

    public func contains(day: Int, today: Int) -> Bool {
        guard let start = startDay(today: today) else { return day <= today }
        return day >= start && day <= today
    }
}

public enum SeriesTools {
    /// Items inside the range, input order kept.
    public static func filter<T>(_ items: [T], day: (T) -> Int, range: ChartRange, today: Int) -> [T] {
        items.filter { range.contains(day: day($0), today: today) }
    }

    /// Thins a long series to about `limit` points so a two-year history stays smooth to scroll: every bucket keeps
    /// its highest point, points flagged by `keep` (records) always survive, and the first and last point stay.
    public static func thin<T>(_ items: [T], limit: Int, value: (T) -> Double, keep: (T) -> Bool = { _ in false }) -> [T] {
        guard limit >= 2, items.count > limit else { return items }
        let bucket = Int((Double(items.count) / Double(limit)).rounded(.up))
        var out: [T] = []
        var index = 0
        while index < items.count {
            let slice = Array(items[index..<min(index + bucket, items.count)])
            var chosen = Set<Int>()
            if let best = slice.indices.max(by: { value(slice[$0]) < value(slice[$1]) }) { chosen.insert(best) }
            for position in slice.indices where keep(slice[position]) { chosen.insert(position) }
            if index == 0 { chosen.insert(0) }
            if index + bucket >= items.count { chosen.insert(slice.count - 1) }
            out += chosen.sorted().map { slice[$0] }
            index += bucket
        }
        return out
    }
}

// MARK: - e1RM series

/// One session of an exercise on the e1RM chart.
public struct ProgressPoint: Sendable, Equatable, Identifiable {
    public var day: Int
    public var date: Date
    public var e1rmKg: Double
    /// Highest e1RM up to this session (strictly above every earlier one).
    public var isRecord: Bool
    public var id: Int { day }
}

/// A stretch of the e1RM chart shaded as plateau.
public struct PlateauZone: Sendable, Equatable {
    public var startDay: Int
    public var endDay: Int

    public init(startDay: Int, endDay: Int) {
        self.startDay = startDay
        self.endDay = endDay
    }
}

public struct TrendPoint: Sendable, Equatable, Identifiable {
    public var day: Int
    public var date: Date
    public var e1rmKg: Double
    public var id: Int { day }
}

public struct ForecastBand: Sendable, Equatable, Identifiable {
    public var weeks: Double
    public var date: Date
    public var e1rmKg: Double
    public var low: Double
    public var high: Double
    public var id: Double { weeks }
}

public enum ProgressSeries {
    /// Marks record sessions (a new all-time best e1RM). The first session is the first record.
    public static func points(_ sessions: [ProgressAnalyzer.Session], calendar: Calendar = .current) -> [ProgressPoint] {
        var best = 0.0
        return sessions.sorted { $0.day < $1.day }.map { session in
            let record = session.e1rmKg > best + 1e-9
            best = max(best, session.e1rmKg)
            return ProgressPoint(
                day: Int(session.day), date: ScoreCalculator.date(ofDay: Int(session.day), calendar: calendar),
                e1rmKg: session.e1rmKg, isRecord: record
            )
        }
    }

    /// The Theil–Sen trend as a straight (in log space) line over the trend window.
    public static func trendLine(_ trend: ProgressAnalyzer.Trend, window: ClosedRange<Int>, calendar: Calendar = .current) -> [TrendPoint] {
        guard trend.status == .ok, let fit = trend.fit, window.count > 1 else { return [] }
        return [window.lowerBound, window.upperBound].map { day in
            TrendPoint(day: day, date: ScoreCalculator.date(ofDay: day, calendar: calendar), e1rmKg: exp(fit.intercept + fit.slope * Double(day)))
        }
    }

    /// 4/8/12-week forecast anchored at the last session.
    public static func forecastBands(_ forecast: ProgressAnalyzer.Forecast, lastDay: Int, calendar: Calendar = .current) -> [ForecastBand] {
        guard forecast.status == .ok else { return [] }
        return forecast.points.map {
            ForecastBand(
                weeks: $0.weeks, date: ScoreCalculator.date(ofDay: lastDay + Int(($0.weeks * 7).rounded()), calendar: calendar),
                e1rmKg: $0.e1rmKg, low: $0.low, high: $0.high
            )
        }
    }

    /// Plateau stretches: the sessions at which the plateau test (over everything up to that session) reports a
    /// plateau, each widened back to the start of the test window, overlapping stretches merged.
    /// Only the newest `maxSessions` sessions are examined to keep this cheap on a two-year history.
    public static func plateauZones(_ sessions: [ProgressAnalyzer.Session], analyzer: ProgressAnalyzer, maxSessions: Int = 150) -> [PlateauZone] {
        let sorted = sessions.sorted { $0.day < $1.day }
        guard sorted.count >= 2 else { return [] }
        let windowDays = Int((analyzer.params.plateau.windowWeeks * 7).rounded())
        let firstIndex = max(0, sorted.count - maxSessions)
        var zones: [PlateauZone] = []
        for index in firstIndex..<sorted.count {
            let prefix = Array(sorted[0...index])
            guard analyzer.plateau(prefix).status == .plateau else { continue }
            let end = Int(sorted[index].day)
            let start = max(Int(sorted[0].day), end - windowDays)
            if let last = zones.last, start <= last.endDay {
                zones[zones.count - 1].endDay = max(last.endDay, end)
            } else {
                zones.append(PlateauZone(startDay: start, endDay: end))
            }
        }
        return zones
    }
}

// MARK: - Weekly volume

/// The coarse muscle groups of the stacked volume bars.
public enum VolumeBucket: String, Sendable, CaseIterable, Identifiable {
    case chest, back, shoulders, arms, legs, core

    public var id: String { rawValue }

    public static func bucket(for muscle: String) -> VolumeBucket? {
        switch muscle {
        case "chest": .chest
        case "lats", "middle_back", "lower_back", "traps", "neck": .back
        case "shoulders": .shoulders
        case "biceps", "triceps", "forearms": .arms
        case "quadriceps", "hamstrings", "glutes", "calves", "adductors", "abductors": .legs
        case "abdominals": .core
        default: nil
        }
    }
}

/// One 7-day window of training volume.
public struct WeekVolume: Sendable, Equatable, Identifiable {
    /// Last day of the window.
    public var endDay: Int
    public var date: Date
    /// Completed working sets (each counted once).
    public var totalSets: Int
    /// Weighted sets (primary 1, secondary 0.5) per muscle group.
    public var buckets: [VolumeBucket: Double]
    public var id: Int { endDay }
}

public enum VolumeSeries {
    /// `weeks` consecutive 7-day windows ending on `endDay`, oldest first.
    public static func weekly(
        _ entries: [VolumeEntry], roles: [String: MuscleRoles], endDay: Int, weeks: Int, calendar: Calendar = .current
    ) -> [WeekVolume] {
        guard weeks > 0 else { return [] }
        return (0..<weeks).map { week in
            let last = endDay - 7 * (weeks - 1 - week)
            let range = (last - 6)...last
            let total = entries.filter { range.contains($0.day) }.reduce(0) { $0 + max(0, $1.sets) }
            var buckets: [VolumeBucket: Double] = [:]
            for (muscle, value) in MuscleVolume.sets(entries, roles: roles, days: range) {
                if let bucket = VolumeBucket.bucket(for: muscle) { buckets[bucket, default: 0] += value }
            }
            return WeekVolume(endDay: last, date: ScoreCalculator.date(ofDay: last, calendar: calendar), totalSets: total, buckets: buckets)
        }
    }

    /// Change of the newest window against the one before it (percent); nil when there is nothing to compare.
    public static func change(_ weeks: [WeekVolume]) -> Double? {
        guard weeks.count >= 2, let previous = weeks.dropLast().last, previous.totalSets > 0, let current = weeks.last else { return nil }
        return Double(current.totalSets - previous.totalSets) / Double(previous.totalSets) * 100
    }
}

// MARK: - Training calendar

/// One day of the six-month calendar heat map.
public struct CalendarCell: Sendable, Equatable, Identifiable {
    public var day: Int
    public var date: Date
    /// Column: week index counted from the first week shown.
    public var week: Int
    /// Row: 0 = the calendar's first weekday.
    public var weekday: Int
    public var workouts: Int
    public var id: Int { day }
}

public enum FrequencyCalendar {
    /// Cells from the start of the week that holds `today − months` to `today`; `workouts` maps day number → finished
    /// workouts of that day.
    public static func cells(workouts: [Int: Int], today: Int, months: Int = 6, calendar: Calendar = .current) -> [CalendarCell] {
        let todayDate = ScoreCalculator.date(ofDay: today, calendar: calendar)
        guard let startDate = calendar.date(byAdding: .month, value: -months, to: todayDate) else { return [] }
        let startDay = ScoreCalculator.dayNumber(startDate, calendar: calendar)
        let startWeekday = weekdayOffset(startDate, calendar: calendar)
        let firstDay = startDay - startWeekday
        return (firstDay...today).map { day in
            let offset = day - firstDay
            return CalendarCell(
                day: day, date: ScoreCalculator.date(ofDay: day, calendar: calendar), week: offset / 7, weekday: offset % 7,
                workouts: workouts[day] ?? 0
            )
        }
    }

    /// 0 for the calendar's first weekday … 6.
    static func weekdayOffset(_ date: Date, calendar: Calendar) -> Int {
        (calendar.component(.weekday, from: date) - calendar.firstWeekday + 7) % 7
    }

    /// Counts finished workouts per day number.
    public static func perDay(_ dates: [Date], calendar: Calendar = .current) -> [Int: Int] {
        var out: [Int: Int] = [:]
        for date in dates { out[ScoreCalculator.dayNumber(date, calendar: calendar), default: 0] += 1 }
        return out
    }
}

// MARK: - Bodyweight and relative strength

public struct BodyweightPoint: Sendable, Equatable, Identifiable {
    public var day: Int
    public var date: Date
    public var weightKg: Double
    public var id: Int { day }

    public init(day: Int, date: Date, weightKg: Double) {
        self.day = day
        self.date = date
        self.weightKg = weightKg
    }
}

public struct RelativePoint: Sendable, Equatable, Identifiable {
    public var day: Int
    public var date: Date
    /// e1RM divided by the bodyweight of that time.
    public var ratio: Double
    public var id: Int { day }
}

public enum RelativeStrength {
    /// e1RM ÷ the newest bodyweight at or before the session; sessions before the first weigh-in use the first one.
    public static func series(_ points: [ProgressPoint], bodyweights: [BodyweightPoint]) -> [RelativePoint] {
        let weights = bodyweights.sorted { $0.day < $1.day }
        guard !weights.isEmpty else { return [] }
        return points.sorted { $0.day < $1.day }.compactMap { point in
            let weight = weights.last { $0.day <= point.day } ?? weights[0]
            guard weight.weightKg > 0 else { return nil }
            return RelativePoint(day: point.day, date: point.date, ratio: point.e1rmKg / weight.weightKg)
        }
    }
}

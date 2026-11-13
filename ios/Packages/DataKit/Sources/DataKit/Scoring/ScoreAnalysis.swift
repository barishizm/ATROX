import Foundation
import StrengthKit

// Pure helpers behind the Analysis (P066) and Today (P067) tabs: training volume per muscle, what feeds a muscle's
// score, score changes over time, weekly activity and the dashboard state. No storage, no UI.

// MARK: - Volume

/// Completed working sets of one exercise on one day.
public struct VolumeEntry: Sendable, Equatable {
    public var day: Int
    public var exerciseId: String
    public var sets: Int

    public init(day: Int, exerciseId: String, sets: Int) {
        self.day = day
        self.exerciseId = exerciseId
        self.sets = sets
    }
}

public struct MuscleRoles: Sendable, Equatable {
    public var primary: [String]
    public var secondary: [String]

    public init(primary: [String], secondary: [String] = []) {
        self.primary = primary
        self.secondary = secondary
    }
}

/// Weekly volume rule (docs/ANTRENMAN-MANTIGI.md): a set counts 1 for each primary muscle and 0.5 for each secondary
/// muscle; a muscle listed as both counts as primary.
public enum MuscleVolume {
    public static let primaryWeight = 1.0
    public static let secondaryWeight = 0.5

    /// Weighted sets per muscle over the inclusive day range. Exercises without roles (custom) are ignored.
    public static func sets(_ entries: [VolumeEntry], roles: [String: MuscleRoles], days: ClosedRange<Int>) -> [String: Double] {
        var out: [String: Double] = [:]
        for entry in entries where days.contains(entry.day) && entry.sets > 0 {
            guard let role = roles[entry.exerciseId] else { continue }
            let count = Double(entry.sets)
            for muscle in role.secondary where !role.primary.contains(muscle) { out[muscle, default: 0] += count * secondaryWeight }
            for muscle in Set(role.primary) { out[muscle, default: 0] += count * primaryWeight }
        }
        return out
    }

    /// Weighted sets per muscle in each of the last `weeks` 7-day windows ending on `endDay`, oldest first.
    /// A muscle with no sets in any window is absent.
    public static func weekly(_ entries: [VolumeEntry], roles: [String: MuscleRoles], endDay: Int, weeks: Int = 4) -> [String: [Double]] {
        var out: [String: [Double]] = [:]
        for week in 0..<weeks {
            let last = endDay - 7 * (weeks - 1 - week)
            for (muscle, value) in sets(entries, roles: roles, days: (last - 6)...last) {
                out[muscle, default: Array(repeating: 0, count: weeks)][week] = value
            }
        }
        return out
    }
}

// MARK: - Muscle score detail

/// One exercise behind a muscle's score.
public struct MuscleContribution: Sendable, Equatable, Identifiable {
    public enum Role: String, Sendable { case primary, secondary }

    public var exerciseId: String
    public var role: Role
    public var score: Double
    /// Share of the muscle's score weight, 0…1 (role weights only: 1.0 primary, 0.4 secondary).
    public var share: Double
    public var id: String { exerciseId }
}

public enum MuscleContributions {
    /// Scored exercises that train `muscle`, biggest share first.
    public static func contributions(muscle: String, overview: ScoreOverview, model: StrengthModel) -> [MuscleContribution] {
        let weights = model.params.aggregate.muscleWeights
        var items: [MuscleContribution] = []
        var shares: [String: Double] = [:]
        for id in overview.exercises.keys.sorted() {
            guard let evaluation = overview.exercises[id], let exercise = try? model.exercise(id) else { continue }
            let role: MuscleContribution.Role
            if exercise.primaryMuscles.contains(muscle) {
                role = .primary
            } else if exercise.secondaryMuscles.contains(muscle) {
                role = .secondary
            } else {
                continue
            }
            let weight = role == .primary ? weights.primary : weights.secondary
            shares[id] = weight
            items.append(MuscleContribution(exerciseId: id, role: role, score: evaluation.score.score, share: weight))
        }
        let total = shares.values.reduce(0, +)
        guard total > 0 else { return [] }
        return items
            .map { MuscleContribution(exerciseId: $0.exerciseId, role: $0.role, score: $0.score, share: $0.share / total) }
            .sorted { ($0.share, $0.score, $1.exerciseId) > ($1.share, $1.score, $0.exerciseId) }
    }
}

// MARK: - Ranking

public enum MuscleRanking {
    /// Keys of the `count` lowest scores, weakest first. Empty unless more than `count` muscles are scored (otherwise
    /// every muscle would be "weakest").
    public static func weakest(_ scores: [String: Double], count: Int = 3) -> [String] {
        guard scores.count > count else { return [] }
        return scores.sorted { ($0.value, $0.key) < ($1.value, $1.key) }.prefix(count).map(\.key)
    }
}

// MARK: - Score changes

public struct ScorePoint: Sendable, Equatable {
    public var date: Date
    public var score: Double

    public init(date: Date, score: Double) {
        self.date = date
        self.score = score
    }
}

public enum ScoreTrend {
    /// A series younger than this has no meaningful change yet.
    public static let minimumSpanDays = 7

    /// Change of the current score (`current`, else the series' last point) against the last point at least `days` old.
    /// A series that is shorter than `days` falls back to its first point when that is at least a week old; nil when
    /// there is nothing to compare with.
    public static func change(_ series: [ScorePoint], current: Double? = nil, now: Date, days: Int = 30, calendar: Calendar = .current) -> Double? {
        let sorted = series.sorted { $0.date < $1.date }
        guard let latest = sorted.last, let cutoff = calendar.date(byAdding: .day, value: -days, to: now) else { return nil }
        let reference: ScorePoint
        if let old = sorted.last(where: { $0.date <= cutoff }) {
            reference = old
        } else if let first = sorted.first, let weekAgo = calendar.date(byAdding: .day, value: -minimumSpanDays, to: now), first.date <= weekAgo {
            reference = first
        } else {
            return nil
        }
        return (current ?? latest.score) - reference.score
    }

    /// The key with the biggest gain of at least `minimum` points (ties: smaller key).
    public static func mostImproved(
        _ series: [String: [ScorePoint]], now: Date, days: Int = 30, minimum: Double = 1, calendar: Calendar = .current
    ) -> (key: String, change: Double)? {
        var best: (key: String, change: Double)?
        for key in series.keys.sorted() {
            guard let value = change(series[key] ?? [], now: now, days: days, calendar: calendar), value >= minimum else { continue }
            if best == nil || value > best!.change { best = (key, value) }
        }
        return best
    }
}

// MARK: - Weekly activity

public enum WeeklyActivity {
    /// Finished workouts per calendar week over the last `weeks` weeks; the last element is the current week.
    public static func counts(_ dates: [Date], now: Date, weeks: Int, calendar: Calendar = .current) -> [Int] {
        guard weeks > 0, let current = calendar.dateInterval(of: .weekOfYear, for: now)?.start else { return [] }
        let starts = (0..<weeks).compactMap { calendar.date(byAdding: .weekOfYear, value: -(weeks - 1 - $0), to: current) }
        guard starts.count == weeks, let end = calendar.date(byAdding: .weekOfYear, value: 1, to: current) else { return [] }
        var counts = Array(repeating: 0, count: weeks)
        for date in dates where date >= starts[0] && date < end {
            if let index = starts.lastIndex(where: { $0 <= date }) { counts[index] += 1 }
        }
        return counts
    }

    /// Consecutive weeks that reached `goal` workouts. The running week counts once it is met and never breaks the
    /// streak while it is still open.
    public static func streak(counts: [Int], goal: Int) -> Int {
        let target = max(1, goal)
        var streak = (counts.last ?? 0) >= target ? 1 : 0
        for count in counts.dropLast().reversed() {
            guard count >= target else { break }
            streak += 1
        }
        return streak
    }
}

// MARK: - Today dashboard

/// What the Today score card shows.
public enum DashboardStatus: Sendable, Equatable {
    /// No scorable exercise logged yet.
    case noData
    /// Overall score exists but too few patterns / no upper + lower coverage; `missing` lists patterns still open.
    case provisional(missing: [String])
    case full

    public static func make(overall: GroupScore?, allPatterns: [String]) -> DashboardStatus {
        make(hasOverall: overall != nil, provisional: overall?.provisional ?? false, covered: overall?.patterns ?? [], allPatterns: allPatterns)
    }

    public static func make(hasOverall: Bool, provisional: Bool, covered: [String], allPatterns: [String]) -> DashboardStatus {
        guard hasOverall else { return .noData }
        guard provisional else { return .full }
        return .provisional(missing: allPatterns.filter { !covered.contains($0) })
    }
}

public enum PatternSuggestion {
    /// A well-known scored exercise that fills a movement pattern ("tamamlamak için şunu kaydet").
    public static func exerciseId(for pattern: String) -> String? {
        [
            "horizontal_push": "barbell-bench-press-medium-grip", "vertical_push": "barbell-shoulder-press",
            "horizontal_pull": "bent-over-barbell-row", "vertical_pull": "pullups", "squat": "barbell-full-squat",
            "hip_hinge": "barbell-deadlift", "core": "cable-crunch",
        ][pattern]
    }

    /// The pattern to ask for first: the first open one in the model's pattern order.
    public static func first(missing: [String]) -> String? { missing.first }
}

/// The day of a program to train next.
public enum NextWorkout {
    /// 1) the day planned for today's weekday, 2) the day after the one trained last (wrapping), 3) the first day.
    public static func pick(routine: RoutineSnapshot, weekdayPlan: [Int: UUID], weekday: Int, lastDayId: UUID?) -> RoutineDaySnapshot? {
        let days = routine.days.sorted { $0.position < $1.position }
        guard !days.isEmpty else { return nil }
        if let planned = weekdayPlan[weekday], let day = days.first(where: { $0.id == planned }) { return day }
        if let last = lastDayId, let index = days.firstIndex(where: { $0.id == last }) { return days[(index + 1) % days.count] }
        return days[0]
    }
}

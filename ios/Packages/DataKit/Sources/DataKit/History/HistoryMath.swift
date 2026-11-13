import Foundation
import StrengthKit

/// Pure history numbers (P042): month totals for the calendar and an exercise's progress over time.
public enum HistoryMath {
    // MARK: Calendar

    /// Totals of the finished workouts that started in one calendar month.
    public struct MonthSummary: Sendable, Equatable {
        public let workoutCount: Int
        public let trainedDays: Set<Int>
        public let totalDuration: TimeInterval
        public let totalVolumeKg: Double

        public init(workoutCount: Int, trainedDays: Set<Int>, totalDuration: TimeInterval, totalVolumeKg: Double) {
            self.workoutCount = workoutCount
            self.trainedDays = trainedDays
            self.totalDuration = totalDuration
            self.totalVolumeKg = totalVolumeKg
        }
    }

    /// `[start, end)` of the calendar month containing `date`.
    public static func monthRange(containing date: Date, calendar: Calendar = .current) -> Range<Date> {
        let interval = calendar.dateInterval(of: .month, for: date) ?? DateInterval(start: date, duration: 86_400)
        return interval.start..<interval.end
    }

    /// Month totals; workouts outside the month are ignored.
    public static func monthSummary(
        of workouts: [WorkoutSnapshot], month: Date, calendar: Calendar = .current
    ) -> MonthSummary {
        let range = monthRange(containing: month, calendar: calendar)
        let inMonth = workouts.filter { range.contains($0.startedAt) && $0.endedAt != nil }
        return MonthSummary(
            workoutCount: inMonth.count,
            trainedDays: Set(inMonth.map { calendar.component(.day, from: $0.startedAt) }),
            totalDuration: inMonth.reduce(0) { $0 + ($1.duration ?? 0) },
            totalVolumeKg: inMonth.reduce(0) { $0 + WorkoutSummary.volume(of: $1) }
        )
    }

    /// Day-of-month numbers (1…31) with a workout, from start dates alone (cheap for a long history).
    public static func trainedDays(
        in dates: [Date], month: Date, calendar: Calendar = .current
    ) -> Set<Int> {
        let range = monthRange(containing: month, calendar: calendar)
        return Set(dates.filter(range.contains).map { calendar.component(.day, from: $0) })
    }

    // MARK: Exercise progress

    public struct ExercisePoint: Sendable, Equatable, Identifiable {
        public var id: Date { date }
        public let date: Date
        public let workoutId: UUID
        /// Best estimated 1RM of the session in kg; nil when no set could be estimated.
        public let e1rmKg: Double?
        public let bestWeightKg: Double
        public let volumeKg: Double
    }

    public struct ExerciseProgress: Sendable, Equatable {
        /// Oldest first (chart order).
        public let points: [ExercisePoint]
        public let heaviest: SetSnapshot?
        public let bestE1rmKg: Double?
        public let lastDate: Date?
        public var sessionCount: Int { points.count }
    }

    /// Progress from an exercise's sessions (as `WorkoutRepository.history` returns them, newest first). Warm-ups and
    /// sets without reps are ignored.
    public static func progress(of sessions: [ExerciseSession]) -> ExerciseProgress {
        var heaviest: SetSnapshot?
        var points: [ExercisePoint] = []
        for session in sessions {
            let counted = session.sets.filter { $0.input.countsForScore }
            guard !counted.isEmpty else { continue }
            let e1rm = counted.compactMap {
                E1RMModel.standard.estimate(weightKg: $0.input.weightKg, reps: $0.input.reps, rir: $0.input.rir)?.valueKg
            }.max()
            for set in counted where set.input.weightKg > (heaviest?.input.weightKg ?? -1) { heaviest = set }
            points.append(
                ExercisePoint(
                    date: session.date, workoutId: session.workoutId, e1rmKg: e1rm,
                    bestWeightKg: counted.map(\.input.weightKg).max() ?? 0,
                    volumeKg: counted.reduce(0) { $0 + $1.input.weightKg * Double($1.input.reps) }
                )
            )
        }
        points.sort { $0.date < $1.date }
        return ExerciseProgress(
            points: points, heaviest: heaviest, bestE1rmKg: points.compactMap(\.e1rmKg).max(), lastDate: points.last?.date
        )
    }
}

import Foundation
import StrengthKit
import SwiftData

/// Reads for the weekly summary (P070).
extension TrainingStats {
    /// The summary of the Monday-to-Sunday week containing `date`.
    public func weeklySummary(
        userId: UUID, weekContaining date: Date, population: ReferencePopulation, goal override: Int? = nil
    ) -> WeeklySummary {
        let context = ModelContext(modelContainer)
        let period = WeekPeriod.containing(date, calendar: calendar)
        let from = period.start, to = period.end
        let records = ((try? context.fetch(FetchDescriptor<PersonalRecord>(
            predicate: #Predicate { $0.userId == userId && $0.deletedAt == nil && $0.exerciseId != nil && $0.date >= from && $0.date < to }
        ))) ?? []).compactMap { row in
            row.exerciseId.map { RecordHighlight(exerciseId: $0, kind: row.kind, value: row.value, date: row.date) }
        }
        let allTime = 36_500
        let overall = snapshotSeries(context: context, userId: userId, scope: .overall, population: population, days: allTime)["overall"] ?? []
        return WeeklySummaryBuilder.build(
            WeeklySummaryInput(
                period: period, workouts: finishedWorkouts(context: context, userId: userId).map(\.startedAt),
                entries: volumeEntries(context: context, userId: userId, sinceDay: period.startDay - 7),
                roles: muscleRoles(context: context), records: records,
                goal: override ?? profileGoal(context: context, userId: userId), overall: overall,
                exercises: snapshotSeries(context: context, userId: userId, scope: .exercise, population: population, days: allTime)
            ),
            calendar: calendar
        )
    }

    /// The weeks to browse, newest first: the week of `now` and `count - 1` before it.
    public func weeklySummaries(userId: UUID, population: ReferencePopulation, count: Int, goal: Int? = nil) -> [WeeklySummary] {
        let now = clock()
        let current = WeekPeriod.containing(now, calendar: calendar)
        return (0..<max(0, count)).map {
            weeklySummary(userId: userId, weekContaining: current.shifted(weeks: -$0, calendar: calendar).start, population: population, goal: goal)
        }
    }
}

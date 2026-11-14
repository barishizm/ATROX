import Foundation

extension TodayModel {
    /// What the widgets and Shortcuts show (P096), derived from the numbers the dashboard just loaded. nil until
    /// the training facts exist.
    func widgetSnapshot(now: Date = Date(), calendar: Calendar = .current) -> WidgetSnapshot? {
        guard let facts else { return nil }
        func widgetDay(_ day: PlannedDay) -> WidgetSnapshot.PlannedDay {
            WidgetSnapshot.PlannedDay(
                routineId: day.routineId, dayId: day.dayId, routineName: day.routineName, dayName: day.dayName,
                exerciseCount: day.exerciseCount
            )
        }
        var next: WidgetSnapshot.PlannedDay?
        if case .planned(let day) = plan { next = widgetDay(day) }
        return WidgetSnapshot(
            generatedAt: now,
            score: overall.map {
                WidgetSnapshot.Score(
                    value: min(max(Int($0.score.rounded()), 0), 100), isProvisional: $0.provisional,
                    change: facts.overallChange.map { Int($0.rounded()) }
                )
            },
            next: next,
            days: Array(programDays.prefix(14).map(widgetDay)),
            weeklyDone: facts.workoutsThisWeek,
            weeklyGoal: facts.goal,
            streakWeeks: facts.streakWeeks,
            trainedToday: facts.trainedToday,
            weekEndsAt: calendar.dateInterval(of: .weekOfYear, for: now)?.end ?? now.addingTimeInterval(7 * 86_400)
        )
    }
}

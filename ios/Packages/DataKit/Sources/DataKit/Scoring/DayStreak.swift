import Foundation

/// Day streak over the weekdays the user chose to train on.
///
/// Only chosen days count: a chosen day with a finished workout extends the streak, a chosen day in the past without
/// one breaks it, and days that were not chosen are ignored entirely (training on them adds nothing, skipping them
/// breaks nothing). Today never breaks the streak while it is still open.
public enum DayStreak {
    /// How far back the walk goes at most.
    public static let lookbackDays = 730

    /// `scheduledWeekdays` use `Calendar` weekday numbers (1 = Sunday … 7 = Saturday).
    public static func current(
        trainedDates: [Date], scheduledWeekdays: Set<Int>, now: Date, calendar: Calendar = .current
    ) -> Int {
        guard !scheduledWeekdays.isEmpty else { return 0 }
        let trained = trainedDays(trainedDates, calendar: calendar)
        var day = calendar.startOfDay(for: now)
        var streak = 0
        if scheduledWeekdays.contains(calendar.component(.weekday, from: day)), trained.contains(day) { streak += 1 }
        for _ in 0..<lookbackDays {
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
            guard scheduledWeekdays.contains(calendar.component(.weekday, from: day)) else { continue }
            guard trained.contains(day) else { break }
            streak += 1
        }
        return streak
    }

    /// The start-of-day of every workout date.
    public static func trainedDays(_ dates: [Date], calendar: Calendar = .current) -> Set<Date> {
        Set(dates.map { calendar.startOfDay(for: $0) })
    }
}

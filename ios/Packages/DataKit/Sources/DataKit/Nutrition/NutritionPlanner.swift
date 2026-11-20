import Foundation

/// How the day's calorie target is split over the meals.
public enum MealBudget {
    /// Share of the daily calories per meal: breakfast 30 %, lunch 40 %, dinner 25 %, snacks 5 %.
    public static func share(of meal: MealType) -> Double {
        switch meal {
        case .breakfast: 0.30
        case .lunch: 0.40
        case .dinner: 0.25
        case .snack: 0.05
        }
    }

    /// Calories per meal for a daily target; the parts always add up to `total`.
    public static func calories(total: Int) -> [MealType: Int] {
        var result: [MealType: Int] = [:]
        var assigned = 0
        for meal in MealType.allCases where meal != .snack {
            let value = Int((Double(total) * share(of: meal)).rounded())
            result[meal] = value
            assigned += value
        }
        result[.snack] = max(total - assigned, 0)
        return result
    }
}

/// Day streak of food logging: consecutive days with at least one entry.
public enum NutritionStreak {
    /// How many days in a row ending today (or yesterday while today is still open) have food logged.
    public static func current(trackedDays: Set<Date>, now: Date, calendar: Calendar = .current) -> Int {
        var day = calendar.startOfDay(for: now)
        if !trackedDays.contains(day) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: day) else { return 0 }
            day = yesterday
        }
        var streak = 0
        while trackedDays.contains(day) {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return streak
    }

    /// The start-of-day of every date.
    public static func trackedDays(_ dates: [Date], calendar: Calendar = .current) -> Set<Date> {
        Set(dates.map { calendar.startOfDay(for: $0) })
    }
}

@testable import DataKit
import Foundation
import Testing

@Suite("Nutrition planner")
struct NutritionPlannerTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private func day(_ offset: Int, from now: Date) -> Date {
        calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now))!
    }

    @Test func mealBudgetsAddUpToTheTarget() {
        let budget = MealBudget.calories(total: 2703)
        #expect(budget[.breakfast] == 811)
        #expect(budget[.lunch] == 1081)
        #expect(budget[.dinner] == 676)
        #expect(budget[.snack] == 135)
        #expect(budget.values.reduce(0, +) == 2703)
    }

    @Test func streakCountsConsecutiveDaysEndingToday() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let tracked: Set<Date> = [day(0, from: now), day(-1, from: now), day(-2, from: now), day(-4, from: now)]
        #expect(NutritionStreak.current(trackedDays: tracked, now: now, calendar: calendar) == 3)
    }

    @Test func openTodayDoesNotBreakTheStreak() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let tracked: Set<Date> = [day(-1, from: now), day(-2, from: now)]
        #expect(NutritionStreak.current(trackedDays: tracked, now: now, calendar: calendar) == 2)
    }

    @Test func aMissedDayResetsTheStreak() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(NutritionStreak.current(trackedDays: [day(-2, from: now)], now: now, calendar: calendar) == 0)
        #expect(NutritionStreak.current(trackedDays: [], now: now, calendar: calendar) == 0)
    }
}

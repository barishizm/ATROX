@testable import DataKit
import Foundation
import Testing

private let calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}()

/// 2026-11-18 is a Wednesday.
private func day(_ d: Int, hour: Int = 18) -> Date {
    calendar.date(from: DateComponents(year: 2026, month: 11, day: d, hour: hour))!
}

@Suite struct DayStreakTests {
    // Monday = 2, Wednesday = 4, Friday = 6
    private let mwf: Set<Int> = [2, 4, 6]

    @Test func noScheduleMeansNoStreak() {
        #expect(DayStreak.current(trainedDates: [day(16)], scheduledWeekdays: [], now: day(18), calendar: calendar) == 0)
    }

    @Test func allChosenDaysTrainedCounts() {
        // Mon 9, Wed 11, Fri 13, Mon 16, Wed 18 (today)
        let dates = [day(9), day(11), day(13), day(16), day(18)]
        #expect(DayStreak.current(trainedDates: dates, scheduledWeekdays: mwf, now: day(18), calendar: calendar) == 5)
    }

    @Test func skippedNonChosenDaysKeepTheStreak() {
        // Tue 17 is not chosen and nothing happened; Mon 16 and Fri 13 were trained.
        let dates = [day(13), day(16)]
        #expect(DayStreak.current(trainedDates: dates, scheduledWeekdays: mwf, now: day(17), calendar: calendar) == 2)
    }

    @Test func trainingOnNonChosenDaysAddsNothing() {
        let dates = [day(16), day(17)]
        #expect(DayStreak.current(trainedDates: dates, scheduledWeekdays: mwf, now: day(17), calendar: calendar) == 1)
    }

    @Test func openTodayDoesNotBreak() {
        let dates = [day(13), day(16)]
        #expect(DayStreak.current(trainedDates: dates, scheduledWeekdays: mwf, now: day(18), calendar: calendar) == 2)
    }

    @Test func missedChosenDayBreaks() {
        // Wed 11 missed; Mon 9 and Fri 13, Mon 16 trained.
        let dates = [day(9), day(13), day(16)]
        #expect(DayStreak.current(trainedDates: dates, scheduledWeekdays: mwf, now: day(18), calendar: calendar) == 2)
    }

    @Test func multipleWorkoutsOnOneDayCountOnce() {
        let dates = [day(16, hour: 8), day(16, hour: 19)]
        #expect(DayStreak.current(trainedDates: dates, scheduledWeekdays: mwf, now: day(16), calendar: calendar) == 1)
    }
}

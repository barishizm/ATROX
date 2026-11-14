@testable import DataKit
import Foundation
import Testing

private func calendar(_ zone: String) -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: zone)!
    return calendar
}

private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12, _ min: Int = 0, zone: String = "UTC") -> Date {
    calendar(zone).date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
}

private let roles: [String: MuscleRoles] = [
    "bench": MuscleRoles(primary: ["chest"], secondary: ["triceps"]),
    "squat": MuscleRoles(primary: ["quadriceps"]),
]

@Suite("Weekly summary (P070)")
struct WeeklySummaryTests {
    // 2026-11-09 is a Monday.
    @Test func weekRunsMondayToSundayWhateverTheLocale() {
        var us = calendar("UTC")
        us.firstWeekday = 1
        let period = WeekPeriod.containing(date(2026, 11, 15, 23, 30), calendar: us)
        #expect(period.start == date(2026, 11, 9, 0, 0))
        #expect(period.end == date(2026, 11, 16, 0, 0))
        #expect(period.endDay - period.startDay == 6)
        // Monday 00:00 belongs to the new week, Sunday 23:59 to the old one.
        #expect(WeekPeriod.containing(date(2026, 11, 16, 0, 0), calendar: us).start == date(2026, 11, 16, 0, 0))
        #expect(WeekPeriod.containing(date(2026, 11, 15, 23, 59), calendar: us).start == date(2026, 11, 9, 0, 0))
    }

    @Test func weekBoundaryFollowsTheUsersTimeZone() {
        let tokyo = calendar("Asia/Tokyo")
        // Sunday 23:30 in Tokyo is still Sunday 14:30 UTC: same week; Monday 00:30 Tokyo is Sunday 15:30 UTC: next week.
        let sunday = date(2026, 11, 15, 23, 30, zone: "Asia/Tokyo")
        let monday = date(2026, 11, 16, 0, 30, zone: "Asia/Tokyo")
        #expect(WeekPeriod.containing(sunday, calendar: tokyo).start != WeekPeriod.containing(monday, calendar: tokyo).start)
        #expect(WeekPeriod.containing(monday, calendar: tokyo).start == date(2026, 11, 16, 0, 0, zone: "Asia/Tokyo"))
        let utc = calendar("UTC")
        #expect(WeekPeriod.containing(monday, calendar: utc).start == date(2026, 11, 9, 0, 0))
    }

    @Test func weekSurvivesDaylightSavingShift() {
        let berlin = calendar("Europe/Berlin")
        // Clocks go back on Sunday 2026-10-25: the week has 7 days but 169 hours.
        let period = WeekPeriod.containing(date(2026, 10, 25, 12, zone: "Europe/Berlin"), calendar: berlin)
        #expect(period.start == date(2026, 10, 19, 0, 0, zone: "Europe/Berlin"))
        #expect(period.end == date(2026, 10, 26, 0, 0, zone: "Europe/Berlin"))
        #expect(period.endDay - period.startDay == 6)
        #expect(period.shifted(weeks: -1, calendar: berlin).end == period.start)
    }

    private func input(period: WeekPeriod, workouts: [Date], entries: [VolumeEntry]) -> WeeklySummaryInput {
        WeeklySummaryInput(period: period, workouts: workouts, entries: entries, roles: roles, records: [], goal: 3, overall: [], exercises: [:])
    }

    @Test func countsVolumeAndComparesWithThePreviousWeek() {
        let utc = calendar("UTC")
        let period = WeekPeriod.containing(date(2026, 11, 12), calendar: utc)
        let entries = [
            VolumeEntry(day: period.startDay - 3, exerciseId: "bench", sets: 10),
            VolumeEntry(day: period.startDay + 1, exerciseId: "bench", sets: 9),
            VolumeEntry(day: period.startDay + 3, exerciseId: "squat", sets: 6),
        ]
        let workouts = [date(2026, 11, 6), date(2026, 11, 10), date(2026, 11, 12), date(2026, 11, 17)]
        let summary = WeeklySummaryBuilder.build(input(period: period, workouts: workouts, entries: entries), calendar: utc)
        #expect(summary.workouts == 2)
        #expect(summary.totalSets == 15)
        #expect(summary.previousSets == 10)
        #expect(summary.volumeChange == 50)
        #expect(summary.topGroup == .chest)
        #expect(summary.neglectedGroups.contains(.back))
        #expect(!summary.neglectedGroups.contains(.legs))
        #expect(!summary.metGoal)
    }

    @Test func recordsAndScoreMovesAreFilteredToTheWeek() {
        let utc = calendar("UTC")
        let period = WeekPeriod.containing(date(2026, 11, 12), calendar: utc)
        var base = input(period: period, workouts: [date(2026, 11, 10)], entries: [])
        base.records = [
            RecordHighlight(exerciseId: "bench", kind: .e1rm, value: 100, date: date(2026, 11, 10)),
            RecordHighlight(exerciseId: "squat", kind: .weight, value: 140, date: date(2026, 11, 2)),
        ]
        base.overall = [ScorePoint(date: date(2026, 11, 2), score: 50), ScorePoint(date: date(2026, 11, 11), score: 53.2)]
        base.exercises = [
            "bench": [ScorePoint(date: date(2026, 11, 2), score: 60), ScorePoint(date: date(2026, 11, 11), score: 64)],
            "squat": [ScorePoint(date: date(2026, 11, 2), score: 70), ScorePoint(date: date(2026, 11, 11), score: 70.2)],
            "row": [ScorePoint(date: date(2026, 11, 11), score: 40)],
        ]
        let summary = WeeklySummaryBuilder.build(base, calendar: utc)
        #expect(summary.records.map(\.exerciseId) == ["bench"])
        #expect(summary.overallScore == 53.2)
        #expect(abs((summary.overallChange ?? 0) - 3.2) < 1e-9)
        // Noise (squat) and series without a base point (row) are dropped.
        #expect(summary.exerciseChanges.map(\.key) == ["bench"])
    }

    @Test func emptyWeekIsEmptyAndHasNoComparisons() {
        let utc = calendar("UTC")
        let period = WeekPeriod.containing(date(2026, 11, 12), calendar: utc)
        let summary = WeeklySummaryBuilder.build(input(period: period, workouts: [], entries: []), calendar: utc)
        #expect(summary.isEmpty)
        #expect(summary.totalSets == 0)
        #expect(summary.volumeChange == nil)
        #expect(summary.topGroup == nil)
        #expect(summary.neglectedGroups.isEmpty)
        #expect(summary.overallChange == nil)
    }

    @Test func nextFireIsTheComingSundayEveningInLocalTime() {
        let berlin = calendar("Europe/Berlin")
        // Wednesday -> that Sunday at 19:00.
        #expect(WeeklySchedule.nextFire(after: date(2026, 11, 11, 10, zone: "Europe/Berlin"), hour: 19, calendar: berlin)
            == date(2026, 11, 15, 19, 0, zone: "Europe/Berlin"))
        // Sunday 20:00 is already past 19:00 -> next week.
        #expect(WeeklySchedule.nextFire(after: date(2026, 11, 15, 20, zone: "Europe/Berlin"), hour: 19, calendar: berlin)
            == date(2026, 11, 22, 19, 0, zone: "Europe/Berlin"))
        // Across the DST change the wall-clock hour stays 19:00.
        #expect(WeeklySchedule.nextFire(after: date(2026, 10, 22, 10, zone: "Europe/Berlin"), hour: 19, calendar: berlin)
            == date(2026, 10, 25, 19, 0, zone: "Europe/Berlin"))
    }
}

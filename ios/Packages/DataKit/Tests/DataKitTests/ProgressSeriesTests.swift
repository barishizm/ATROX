@testable import DataKit
import Foundation
import StrengthKit
import Testing

private let utc: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    calendar.firstWeekday = 2
    return calendar
}()

private func analyzer() throws -> ProgressAnalyzer {
    ProgressAnalyzer(params: try EmbeddedModelBundle.model().params.progress)
}

/// Three sessions a week: `rising` weeks of ~1.5 % per week, then `flat` weeks without any gain (tiny deterministic wobble).
private func sessions(rising: Int, flat: Int) -> [ProgressAnalyzer.Session] {
    var out: [ProgressAnalyzer.Session] = []
    var value = 100.0
    for week in 0..<(rising + flat) {
        if week < rising { value *= 1.015 }
        for slot in 0..<3 {
            let wobble = [0.0, 0.004, -0.004][slot] * value
            out.append(ProgressAnalyzer.Session(day: Double(week * 7 + slot * 2), e1rmKg: value + wobble))
        }
    }
    return out
}

@Suite struct ChartRangeTests {
    @Test func rangesReachBackTheirDaysAndAllIsUnbounded() {
        #expect(ChartRange.month.startDay(today: 1000) == 970)
        #expect(ChartRange.year.startDay(today: 1000) == 635)
        #expect(ChartRange.all.startDay(today: 1000) == nil)
        #expect(ChartRange.quarter.contains(day: 910, today: 1000))
        #expect(!ChartRange.quarter.contains(day: 900, today: 1000))
        #expect(!ChartRange.month.contains(day: 1001, today: 1000))
        #expect(ChartRange.all.contains(day: -50, today: 1000))
    }

    @Test func filterKeepsOrderAndDropsOutsiders() {
        let kept = SeriesTools.filter([990, 900, 1000, 1010], day: { $0 }, range: .month, today: 1000)
        #expect(kept == [990, 1000])
    }

    @Test func thinKeepsEndsRecordsAndStaysNearTheLimit() {
        let items = (0..<2_000).map { ($0, Double($0 % 97)) }
        let thinned = SeriesTools.thin(items, limit: 200, value: { $0.1 }, keep: { $0.0 == 777 })
        #expect(thinned.count <= 260)
        #expect(thinned.first?.0 == 0 && thinned.last?.0 == 1_999)
        #expect(thinned.contains { $0.0 == 777 })
        #expect(zip(thinned, thinned.dropFirst()).allSatisfy { $0.0 < $1.0 })
        let short = Array(items.prefix(50))
        #expect(SeriesTools.thin(short, limit: 200, value: { $0.1 }).count == 50)
    }
}

@Suite struct ProgressSeriesTests {
    @Test func marksRecordSessionsOnly() {
        let input = [(0, 100.0), (3, 105.0), (6, 103.0), (9, 105.0), (12, 108.0)].map { ProgressAnalyzer.Session(day: Double($0.0), e1rmKg: $0.1) }
        let points = ProgressSeries.points(input, calendar: utc)
        #expect(points.map(\.isRecord) == [true, true, false, false, true])
        #expect(points.map(\.day) == [0, 3, 6, 9, 12])
    }

    @Test func steadyProgressHasNoPlateauZone() throws {
        let zones = ProgressSeries.plateauZones(sessions(rising: 24, flat: 0), analyzer: try analyzer())
        #expect(zones.isEmpty)
    }

    @Test func aFlatStretchAfterProgressBecomesAZoneThatStartsLate() throws {
        let data = sessions(rising: 12, flat: 14)
        let zones = ProgressSeries.plateauZones(data, analyzer: try analyzer())
        let zone = try #require(zones.first)
        #expect(zone.startDay >= 12 * 7 - 6 * 7)
        #expect(zone.endDay == Int(data.last?.day ?? 0))
        #expect(zones.count == 1)
    }

    @Test func forecastAndTrendLineExistForAClearTrend() throws {
        let data = sessions(rising: 20, flat: 0)
        let progress = ScoreService.progress("x", sessions: data, params: try EmbeddedModelBundle.model().params.progress, percentile: 50, trainingYears: nil, today: 140, calendar: utc)
        #expect(progress.trend.status == .ok)
        #expect(progress.trendLine.count == 2 && progress.trendLine[1].e1rmKg > progress.trendLine[0].e1rmKg)
        #expect(progress.forecast.map(\.weeks) == [4, 8, 12])
        #expect(progress.forecast.allSatisfy { $0.low <= $0.e1rmKg && $0.e1rmKg <= $0.high })
        #expect(progress.forecast.last!.high - progress.forecast.last!.low > progress.forecast.first!.high - progress.forecast.first!.low)
        #expect(progress.score.status == .ok)
    }

    @Test func tooFewSessionsGiveNoTrendOrForecast() throws {
        let data = [ProgressAnalyzer.Session(day: 0, e1rmKg: 100), ProgressAnalyzer.Session(day: 7, e1rmKg: 102)]
        let progress = ScoreService.progress("x", sessions: data, params: try EmbeddedModelBundle.model().params.progress, percentile: 50, trainingYears: nil, today: 10, calendar: utc)
        #expect(progress.trend.status == .insufficientData)
        #expect(progress.trendLine.isEmpty && progress.forecast.isEmpty && progress.plateauZones.isEmpty)
        #expect(progress.points.count == 2)
    }

    @Test func twoYearHistoryPreparesQuickly() throws {
        let data = sessions(rising: 60, flat: 45)
        let started = Date()
        let progress = ScoreService.progress("x", sessions: data, params: try EmbeddedModelBundle.model().params.progress, percentile: 50, trainingYears: nil, today: 735, calendar: utc)
        #expect(progress.points.count == 315)
        #expect(Date().timeIntervalSince(started) < 5)
    }
}

@Suite struct VolumeSeriesTests {
    private let roles: [String: MuscleRoles] = [
        "bench": MuscleRoles(primary: ["chest"], secondary: ["triceps", "shoulders"]),
        "row": MuscleRoles(primary: ["lats", "middle_back"], secondary: ["biceps"]),
        "squat": MuscleRoles(primary: ["quadriceps", "glutes"], secondary: ["hamstrings", "lower_back"]),
    ]

    @Test func weeksAreSevenDayWindowsWithRawTotalsAndGroupedWeightedSets() {
        let entries = [
            VolumeEntry(day: 100, exerciseId: "bench", sets: 4), VolumeEntry(day: 99, exerciseId: "row", sets: 3),
            VolumeEntry(day: 93, exerciseId: "squat", sets: 5), VolumeEntry(day: 70, exerciseId: "bench", sets: 9),
        ]
        let weeks = VolumeSeries.weekly(entries, roles: roles, endDay: 100, weeks: 3, calendar: utc)
        #expect(weeks.map(\.endDay) == [86, 93, 100])
        #expect(weeks.map(\.totalSets) == [0, 5, 7])
        let last = weeks[2]
        #expect(last.buckets[.chest] == 4)
        #expect(last.buckets[.back] == 6)        // lats 3 + middle back 3
        #expect(last.buckets[.arms] == 2 + 1.5)  // triceps 4 × 0.5 + biceps 3 × 0.5
        #expect(last.buckets[.shoulders] == 2)
        #expect(weeks[1].buckets[.legs] == 5 + 5 + 2.5)  // quads 5, glutes 5, hamstrings 2.5; lower back goes to back
        #expect(weeks[1].buckets[.back] == 2.5)
        #expect(weeks[0].buckets.isEmpty)
    }

    @Test func changeComparesTheNewestWeekWithTheOneBefore() {
        func week(_ day: Int, _ sets: Int) -> WeekVolume { WeekVolume(endDay: day, date: Date(), totalSets: sets, buckets: [:]) }
        #expect(VolumeSeries.change([week(1, 10), week(8, 15)]) == 50)
        #expect(VolumeSeries.change([week(1, 0), week(8, 15)]) == nil)
        #expect(VolumeSeries.change([week(8, 15)]) == nil)
    }
}

@Suite struct FrequencyCalendarTests {
    @Test func cellsRunFromTheWeekStartToTodayWithWeekdayRows() throws {
        // 2026-11-14 is a Saturday; weeks start on Monday.
        let today = ScoreCalculator.dayNumber(Date(timeIntervalSince1970: 1_794_657_600), calendar: utc)
        let cells = FrequencyCalendar.cells(workouts: [today: 2, today - 1: 1], today: today, months: 6, calendar: utc)
        let last = try #require(cells.last)
        #expect(last.day == today && last.workouts == 2 && last.weekday == 5)
        #expect(cells.first?.weekday == 0)
        #expect(cells.count % 7 == (today - cells[0].day + 1) % 7)
        #expect(Set(cells.map(\.week)).count >= 26)
        #expect(cells.first { $0.day == today - 1 }?.workouts == 1)
        #expect(cells.first { $0.day == today - 2 }?.workouts == 0)
    }

    @Test func perDayCountsWorkoutsOfTheSameDay() {
        let morning = Date(timeIntervalSince1970: 1_794_657_600 - 7_200), evening = Date(timeIntervalSince1970: 1_794_657_600 + 3_600)
        let counts = FrequencyCalendar.perDay([morning, evening, evening.addingTimeInterval(-86_400)], calendar: utc)
        #expect(counts.values.sorted() == [1, 2])
    }
}

@Suite struct RelativeStrengthTests {
    private func point(_ day: Int, _ kg: Double) -> ProgressPoint { ProgressPoint(day: day, date: Date(), e1rmKg: kg, isRecord: false) }
    private func weight(_ day: Int, _ kg: Double) -> BodyweightPoint { BodyweightPoint(day: day, date: Date(), weightKg: kg) }

    @Test func usesTheNewestWeighInAtOrBeforeEachSession() {
        let series = RelativeStrength.series([point(5, 100), point(20, 120), point(40, 120)], bodyweights: [weight(10, 80), weight(30, 75)])
        let expected: [Double] = [100.0 / 80.0, 120.0 / 80.0, 120.0 / 75.0]  // the first session precedes every weigh-in → first one
        #expect(series.map(\.ratio) == expected)
    }

    @Test func noWeighInsMeansNoSeries() {
        #expect(RelativeStrength.series([point(1, 100)], bodyweights: []).isEmpty)
    }
}

import DataKit
import Foundation
import Testing

@testable import ATROX

@Suite struct WeeklySummaryPresenterTests {
    private let en = Locale(identifier: "en")
    private let tr = Locale(identifier: "tr")
    private let names = ["bench": "Bench Press"]

    private func summary(workouts: Int = 3, records: Int = 1) -> WeeklySummary {
        let calendar = Calendar(identifier: .gregorian)
        let period = WeekPeriod.containing(Date(timeIntervalSince1970: 1_800_000_000), calendar: calendar)
        return WeeklySummary(
            period: period, workouts: workouts, goal: 4, totalSets: workouts * 12, previousSets: 30, volumeChange: workouts > 0 ? 20 : nil,
            records: (0..<records).map { _ in RecordHighlight(exerciseId: "bench", kind: .e1rm, value: 100, date: period.start) },
            overallScore: workouts > 0 ? 54.4 : nil, overallChange: workouts > 0 ? 2.6 : nil,
            exerciseChanges: workouts > 0 ? [WeeklyScoreChange(key: "bench", change: 3.2)] : [],
            topGroup: workouts > 0 ? .chest : nil, neglectedGroups: workouts > 0 ? [.legs] : []
        )
    }

    @Test func fullWeekHasEveryCardWithoutUnresolvedKeysInBothLanguages() {
        for locale in [en, tr] {
            let cards = WeeklySummaryPresenter.cards(for: summary(), names: names, locale: locale, insight: nil)
            #expect(cards.map(\.kind) == [.workouts, .volume, .records, .scores, .muscles, .coach])
            for card in cards {
                for text in [card.title, card.value] + card.lines {
                    #expect(!text.contains("weekly."), "unresolved key in \(locale.identifier): \(text)")
                    #expect(text.range(of: "%[@d]|%lld", options: .regularExpression) == nil, "unfilled format in \(locale.identifier): \(text)")
                }
            }
        }
    }

    @Test func workoutCardShowsProgressAgainstTheGoal() {
        let cards = WeeklySummaryPresenter.cards(for: summary(workouts: 3), names: names, locale: en, insight: nil)
        #expect(cards.first?.value == "3/4")
        #expect(cards.first?.lines == ["1 more to reach your goal."])
        let scores = cards.first { $0.kind == .scores }
        #expect(scores?.value == "+3")
        #expect(scores?.lines.contains("Bench Press: +3") == true)
    }

    @Test func emptyWeekShowsOnlyAGentleRestartAndTheCoachPlaceholder() {
        let cards = WeeklySummaryPresenter.cards(for: summary(workouts: 0, records: 0), names: names, locale: tr, insight: nil)
        #expect(cards.map(\.kind) == [.restart, .coach])
        #expect(cards[0].title == "Yeniden başlamak için güzel bir an")
    }

    @Test func notificationTextFollowsTheWeek() {
        #expect(WeeklySummaryPresenter.notification(for: summary(workouts: 3, records: 2), locale: en).body == "3 of 4 workouts and 2 new records this week.")
        #expect(WeeklySummaryPresenter.notification(for: summary(workouts: 3, records: 0), locale: tr).body == "Bu hafta 3/4 antrenman tamamlandı.")
        let empty = WeeklySummaryPresenter.notification(for: summary(workouts: 0, records: 0), locale: en)
        #expect(empty.body == "A quiet week. Open your summary and plan a short restart.")
        #expect(WeeklySummaryPresenter.notification(for: nil, locale: en).body == empty.body)
    }
}

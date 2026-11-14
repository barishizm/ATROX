import DataKit
import Foundation
import Observation

/// The weekly summary screen (P070): the current week and the weeks before it.
@MainActor
@Observable
final class WeeklySummaryModel {
    struct Week: Identifiable, Equatable {
        let summary: WeeklySummary
        let title: String
        let isCurrent: Bool
        let cards: [WeeklyCard]

        var id: Int { summary.id }
    }

    static let weekCount = 8

    private(set) var weeks: [Week] = []
    private(set) var isLoading = true
    var selectedId: Int?

    @ObservationIgnored private let context: HistoryContext
    @ObservationIgnored private let stats: TrainingStats
    @ObservationIgnored private let scores: ScoreService
    @ObservationIgnored private let insights: InsightService
    @ObservationIgnored private let calendar: Calendar

    init(context: HistoryContext, stats: TrainingStats, scores: ScoreService, insights: InsightService, calendar: Calendar = .current) {
        self.context = context
        self.stats = stats
        self.scores = scores
        self.insights = insights
        self.calendar = calendar
    }

    var selected: Week? { weeks.first { $0.id == selectedId } ?? weeks.first }

    func load() async {
        let names = await context.loadNames()
        let population = await scores.preferredPopulation(userId: context.userId)
        let summaries = await stats.weeklySummaries(userId: context.userId, population: population, count: Self.weekCount)
        let insight = await insights.current(userId: context.userId).first
            .map { InsightPresenter.item(for: $0, names: names, locale: context.locale) }
        weeks = summaries.enumerated().map { index, summary in
            Week(
                summary: summary, title: WeeklySummaryPresenter.rangeTitle(summary.period, locale: context.locale, calendar: calendar),
                isCurrent: index == 0,
                cards: WeeklySummaryPresenter.cards(for: summary, names: names, locale: context.locale, insight: index == 0 ? insight : nil)
            )
        }
        if selectedId == nil || !weeks.contains(where: { $0.id == selectedId }) { selectedId = weeks.first?.id }
        isLoading = false
    }
}

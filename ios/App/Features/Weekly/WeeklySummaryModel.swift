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
    @ObservationIgnored private let comments: CoachCommentProvider?
    @ObservationIgnored private var names: [String: String] = [:]
    @ObservationIgnored private var insight: InsightItem?
    @ObservationIgnored private var commentRequested = false

    init(
        context: HistoryContext, stats: TrainingStats, scores: ScoreService, insights: InsightService, calendar: Calendar = .current,
        comments: CoachCommentProvider? = nil
    ) {
        self.comments = comments
        self.context = context
        self.stats = stats
        self.scores = scores
        self.insights = insights
        self.calendar = calendar
    }

    var selected: Week? { weeks.first { $0.id == selectedId } ?? weeks.first }

    func load() async {
        let names = await context.loadNames()
        self.names = names
        let population = await scores.preferredPopulation(userId: context.userId)
        let summaries = await stats.weeklySummaries(userId: context.userId, population: population, count: Self.weekCount)
        let insight = await insights.current(userId: context.userId).first
            .map { InsightPresenter.item(for: $0, names: names, locale: context.locale) }
        self.insight = insight
        weeks = summaries.enumerated().map { index, summary in
            Week(
                summary: summary, title: WeeklySummaryPresenter.rangeTitle(summary.period, locale: context.locale, calendar: calendar),
                isCurrent: index == 0,
                cards: WeeklySummaryPresenter.cards(for: summary, names: names, locale: context.locale, insight: index == 0 ? insight : nil)
            )
        }
        if selectedId == nil || !weeks.contains(where: { $0.id == selectedId }) { selectedId = weeks.first?.id }
        isLoading = false
        await loadComment()
    }

    // MARK: Coach comment (P083)

    /// The current week's comment, once: a skeleton card while it is written, the text when it arrives, nothing if it
    /// fails or is not available (no consent, switched off, not Pro).
    private func loadComment() async {
        guard !commentRequested, let comments, let current = weeks.first, !current.summary.isEmpty,
              await comments.mightCommentOnWeek() else { return }
        commentRequested = true
        setCoachCard(.loading)
        let language = context.locale.language.languageCode?.identifier == "tr" ? "tr" : "en"
        let digest = CoachDigestBuilder.weekly(current.summary, names: names)
        if let written = await comments.weeklyComment(digest, language: language) {
            setCoachCard(.text(written.text))
        } else {
            setCoachCard(.hidden)
        }
    }

    private func setCoachCard(_ state: CoachCardState) {
        guard let current = weeks.first else { return }
        weeks[0] = Week(
            summary: current.summary, title: current.title, isCurrent: true,
            cards: WeeklySummaryPresenter.cards(for: current.summary, names: names, locale: context.locale, insight: insight, coach: state)
        )
    }
}

import DataKit
import DesignSystem
import Foundation
import Observation
import StrengthKit

/// State of the Today dashboard (P067): the overall strength score, pattern bars, the next workout, highlights,
/// the weekly goal and the streak.
@MainActor
@Observable
final class TodayModel {
    struct PatternBar: Identifiable, Equatable {
        let pattern: String
        /// nil = pattern not covered yet.
        let score: Double?
        var id: String { pattern }
    }

    struct PlannedDay: Equatable {
        let routineId: UUID
        let dayId: UUID
        let routineName: String
        let dayName: String
        let exerciseCount: Int
    }

    enum Plan: Equatable {
        case planned(PlannedDay)
        /// No active program: the template that fits the profile best.
        case suggestion(templateName: String)
        case none
    }

    struct RecordLine: Equatable {
        let exerciseId: String
        let name: String
        let kind: RecordKind
        let valueText: String
        let date: Date
    }

    struct ImprovedLine: Equatable {
        let exerciseId: String
        let name: String
        let change: Int
    }

    private(set) var isLoading = true
    private(set) var status: DashboardStatus = .noData
    private(set) var overall: GroupScore?
    private(set) var bars: [PatternBar] = []
    private(set) var facts: DashboardFacts?
    private(set) var plan: Plan = .none
    private(set) var record: RecordLine?
    private(set) var improved: ImprovedLine?
    private(set) var unavailable: ScoreUnavailable?
    private(set) var hintExerciseId: String?
    private(set) var hintName: String?
    /// The single most important insight of the day (P069); nil when nothing passes the thresholds.
    private(set) var insight: InsightItem?

    let context: HistoryContext
    @ObservationIgnored private let center: ScoreCenter
    @ObservationIgnored private let stats: TrainingStats
    @ObservationIgnored private let planStore: RoutinePlanStore
    @ObservationIgnored private let profile: ProfileInput?
    @ObservationIgnored private let calendar: Calendar
    @ObservationIgnored private let insights: InsightService?

    init(
        context: HistoryContext, center: ScoreCenter, stats: TrainingStats, plan: RoutinePlanStore, profile: ProfileInput?,
        insights: InsightService? = nil, calendar: Calendar = .current
    ) {
        self.context = context
        self.center = center
        self.stats = stats
        planStore = plan
        self.profile = profile
        self.insights = insights
        self.calendar = calendar
    }

    var showsBodyweightReminder: Bool { center.showsBodyweightReminder }

    /// A user without any finished workout sees one clear action instead of an empty dashboard.
    var isNewUser: Bool { (facts?.finishedWorkouts ?? 0) == 0 }

    var weeklyDone: Int { facts?.workoutsThisWeek ?? 0 }
    var weeklyGoal: Int { facts?.goal ?? 3 }
    var streakWeeks: Int { facts?.streakWeeks ?? 0 }

    func load() async {
        let names = await context.loadNames()
        let overview = center.overview
        overall = overview?.overall
        unavailable = overview == nil ? center.unavailable : nil
        status = DashboardStatus.make(overall: overview?.overall, allPatterns: overview?.allPatterns ?? [])
        bars = (overview?.allPatterns ?? []).map { PatternBar(pattern: $0, score: overview?.patterns[$0]?.score) }
        if case .provisional(let missing) = status, let pattern = PatternSuggestion.first(missing: missing),
           let id = PatternSuggestion.exerciseId(for: pattern) {
            hintExerciseId = id
            hintName = names[id]
        } else {
            hintExerciseId = nil
            hintName = nil
        }
        let planned = planStore.dayByWeekday.count
        let loaded = await stats.dashboard(
            userId: context.userId, population: overview?.population ?? .gym, overallScore: overview?.overall?.score,
            goal: planned > 0 ? planned : nil
        )
        facts = loaded
        record = loaded.lastRecord.map {
            RecordLine(exerciseId: $0.exerciseId, name: names[$0.exerciseId] ?? $0.exerciseId, kind: $0.kind, valueText: valueText($0), date: $0.date)
        }
        improved = loaded.mostImproved.map {
            ImprovedLine(exerciseId: $0.exerciseId, name: names[$0.exerciseId] ?? $0.exerciseId, change: Int($0.change.rounded()))
        }
        plan = await resolvePlan()
        await loadInsight(names: names)
        isLoading = false
    }

    private func loadInsight(names: [String: String]) async {
        guard let insights else { return }
        _ = await insights.refresh(userId: context.userId)
        insight = await insights.topForToday(userId: context.userId)
            .map { InsightPresenter.item(for: $0, names: names, locale: context.locale) }
    }

    func dismissInsight() async {
        guard let insight, let insights else { return }
        await insights.dismiss(id: insight.id)
        self.insight = nil
        await load()
    }

    private func valueText(_ record: RecordHighlight) -> String {
        record.kind == .reps ? "\(Int(record.value.rounded()))" : context.weightText(record.value)
    }

    private func resolvePlan() async -> Plan {
        let routines = (try? await context.routines.all(userId: context.userId)) ?? []
        if let id = planStore.activeRoutineId, let routine = routines.first(where: { $0.id == id }) {
            let last = await stats.lastRoutineDayId(userId: context.userId, routineId: routine.id)
            let weekday = calendar.component(.weekday, from: Date())
            if let day = NextWorkout.pick(routine: routine, weekdayPlan: planStore.dayByWeekday, weekday: weekday, lastDayId: last) {
                return .planned(PlannedDay(
                    routineId: routine.id, dayId: day.id, routineName: routine.name, dayName: day.name, exerciseCount: day.exercises.count
                ))
            }
        }
        if let profile, let library = try? TemplateLibrary.bundled(),
           let best = TemplateRecommender.recommend(library.templates, for: TemplateProfile(profile), count: 1).first {
            return .suggestion(templateName: best.template.name.resolve(languageCode: context.languageCode))
        }
        return .none
    }
}

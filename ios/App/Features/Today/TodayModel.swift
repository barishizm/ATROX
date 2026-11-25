import DataKit
import DesignSystem
import Foundation
import Observation
import StrengthKit

/// State of the overall score card (P067) and of the widgets (P096): the overall strength score, the next workout,
/// the weekly goal and the streak.
@MainActor
@Observable
final class TodayModel {
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

    private(set) var isLoading = true
    private(set) var status: DashboardStatus = .noData
    private(set) var overall: GroupScore?
    /// Reference group the overall score was computed against (shown on the share card).
    private(set) var population: ReferencePopulation = .gym
    private(set) var facts: DashboardFacts?
    private(set) var plan: Plan = .none
    /// Every day of the active program (P096: the choices of the "Start workout" shortcut).
    private(set) var programDays: [PlannedDay] = []
    private(set) var unavailable: ScoreUnavailable?
    /// The exercise that would cover a missing pattern of a provisional score.
    private(set) var hintName: String?

    let context: HistoryContext
    @ObservationIgnored private let center: ScoreCenter
    @ObservationIgnored private let stats: TrainingStats
    private let planStore: RoutinePlanStore
    @ObservationIgnored private let profile: ProfileInput?
    @ObservationIgnored private let calendar: Calendar
    /// Hands the overall score to the social layer (P087); the server drops it while sharing is off.
    @ObservationIgnored private let publishScore: (@Sendable (ScorePublication) async -> Bool)?
    @ObservationIgnored private var lastPublished: ScorePublication?

    init(
        context: HistoryContext, center: ScoreCenter, stats: TrainingStats, plan: RoutinePlanStore, profile: ProfileInput?,
        calendar: Calendar = .current,
        publishScore: (@Sendable (ScorePublication) async -> Bool)? = nil
    ) {
        self.publishScore = publishScore
        self.context = context
        self.center = center
        self.stats = stats
        planStore = plan
        self.profile = profile
        self.calendar = calendar
    }

    func load() async {
        let names = await context.loadNames()
        let overview = center.overview
        overall = overview?.overall
        population = overview?.population ?? .gym
        unavailable = overview == nil ? center.unavailable : nil
        status = DashboardStatus.make(overall: overview?.overall, allPatterns: overview?.allPatterns ?? [])
        if case .provisional(let missing) = status, let pattern = PatternSuggestion.first(missing: missing),
           let id = PatternSuggestion.exerciseId(for: pattern) {
            hintName = names[id]
        } else {
            hintName = nil
        }
        let planned = planStore.dayByWeekday.count
        let loaded = await stats.dashboard(
            userId: context.userId, population: overview?.population ?? .gym, overallScore: overview?.overall?.score,
            goal: planned > 0 ? planned : nil
        )
        facts = loaded
        plan = await resolvePlan()
        isLoading = false
        await publishOverall(weekly: loaded.workoutsThisWeek)
    }

    /// Sends the overall score once per change; the server decides whether the user shares it and whether it is plausible.
    private func publishOverall(weekly: Int) async {
        guard let publishScore, let overall else { return }
        let publication = ScorePublication(
            score: min(max(Int(overall.score.rounded()), 1), 99), isProvisional: overall.provisional,
            weeklyWorkouts: min(max(weekly, 0), 50)
        )
        guard publication != lastPublished else { return }
        // Remembered only once the server took it, so a rejected or failed publish is tried again on the next load.
        if await publishScore(publication) { lastPublished = publication }
    }

    /// Changes with the active program and the weekly plan, so the view can reload when either is edited.
    var planSignature: String {
        let week = planStore.dayByWeekday.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value.uuidString)" }.joined(separator: ",")
        return (planStore.activeRoutineId?.uuidString ?? "-") + "|" + week
    }

    private func resolvePlan() async -> Plan {
        let routines = (try? await context.routines.all(userId: context.userId)) ?? []
        programDays = []
        // Templates are split into one program per day, so today's planned weekday may belong to any program,
        // not just the active one.
        let weekday = calendar.component(.weekday, from: Date())
        if let plannedId = planStore.dayByWeekday[weekday],
           let routine = routines.first(where: { $0.days.contains { $0.id == plannedId } }),
           let day = routine.days.first(where: { $0.id == plannedId }) {
            programDays = routine.days.map {
                PlannedDay(routineId: routine.id, dayId: $0.id, routineName: routine.name, dayName: $0.name, exerciseCount: $0.exercises.count)
            }
            return .planned(PlannedDay(
                routineId: routine.id, dayId: day.id, routineName: routine.name, dayName: day.name, exerciseCount: day.exercises.count
            ))
        }
        if let id = planStore.activeRoutineId, let routine = routines.first(where: { $0.id == id }) {
            programDays = routine.days.map {
                PlannedDay(routineId: routine.id, dayId: $0.id, routineName: routine.name, dayName: $0.name, exerciseCount: $0.exercises.count)
            }
            let last = await stats.lastRoutineDayId(userId: context.userId, routineId: routine.id)
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

import Foundation
import StrengthKit
import SwiftData

/// Detects, stores and serves insights (P069). Detection reads scores, history and volume; storage is the synced
/// `InsightRecord` table, so what was shown and dismissed survives restarts and follows the user across devices.
/// Every call uses a fresh `ModelContext`.
public actor InsightService {
    /// Weeks of history the rep-range rule looks at.
    public static let repRangeWeeks = 8

    private let modelContainer: ModelContainer
    private let scores: ScoreService
    private let stats: TrainingStats
    private let clock: @Sendable () -> Date
    private let calendar: Calendar

    public init(
        modelContainer: ModelContainer, scores: ScoreService, stats: TrainingStats, clock: @escaping @Sendable () -> Date = { Date() },
        calendar: Calendar = .current
    ) {
        self.modelContainer = modelContainer
        self.scores = scores
        self.stats = stats
        self.clock = clock
        self.calendar = calendar
    }

    // MARK: Reading

    /// Every stored insight (active, dismissed and past), unordered.
    public func all(userId: UUID) -> [Insight] {
        let context = ModelContext(modelContainer)
        return ((try? context.fetch(InsightRecord.syncDescriptor(.user(userId)))) ?? []).filter { $0.deletedAt == nil }.compactMap(\.insight)
    }

    /// Active, not dismissed insights, best first (the Analysis list).
    public func current(userId: UUID) -> [Insight] {
        InsightSelector.current(all(userId: userId), now: clock(), calendar: calendar)
    }

    public func history(userId: UUID) -> [Insight] {
        InsightSelector.history(all(userId: userId), now: clock(), calendar: calendar)
    }

    /// The one card for Today. Picking it records the showing, which starts the 14-day repeat suppression.
    public func topForToday(userId: UUID) -> Insight? {
        let now = clock()
        guard let top = InsightSelector.top(all(userId: userId), now: now, calendar: calendar) else { return nil }
        let context = ModelContext(modelContainer)
        guard let record = try? context.fetch(InsightRecord.syncDescriptor(.id(top.id))).first else { return top }
        if record.lastShownAt.map({ !calendar.isDate($0, inSameDayAs: now) }) ?? true {
            record.lastShownAt = now
            record.markPending(at: now)
            try? context.save()
        }
        return record.insight
    }

    // MARK: Writing

    public func dismiss(id: UUID) {
        let context = ModelContext(modelContainer)
        guard let record = try? context.fetch(InsightRecord.syncDescriptor(.id(id))).first else { return }
        let now = clock()
        record.dismissedAt = now
        record.markPending(at: now)
        try? context.save()
    }

    // MARK: Detection

    /// Runs the detectors and stores the result: new and changed insights are written, insights whose condition is
    /// gone become inactive. Returns the current list. Does nothing when scores are unavailable.
    @discardableResult
    public func refresh(userId: UUID) async -> [Insight] {
        guard let inputs = await gatherInputs(userId: userId) else { return current(userId: userId) }
        store(InsightEngine.candidates(inputs), userId: userId)
        return current(userId: userId)
    }

    func gatherInputs(userId: UUID) async -> InsightInputs? {
        guard case .ready(let overview) = await scores.overview(userId: userId), let scoring = await scores.currentScoringModel(),
              case .success(let user) = await scores.currentUser(userId: userId),
              let sets = try? await scores.loadScoredSets(userId: userId, exerciseIds: nil) else { return nil }
        let model = scoring.model
        let now = clock()
        let today = ScoreCalculator.dayNumber(now, calendar: calendar)
        let report = await stats.muscleReport(userId: userId)
        let activity = await stats.activity(userId: userId)
        let bodyweight = await scores.bodyweight(userId: userId)
        return InsightInputs(
            imbalances: imbalances(overview: overview, model: model),
            exercises: progressFacts(overview: overview, sets: sets, model: model, user: user),
            weeklyMuscleSets: report.weekly, finishedWorkouts: activity.finishedWorkouts,
            daysSinceLastWorkout: activity.lastWorkoutAt.map { days(from: $0, to: now) },
            bodyweightStaleDays: bodyweight.flatMap { $0.isStale ? days(from: $0.measuredAt, to: now) : nil },
            repBands: repBands(sets, today: today)
        )
    }

    private func imbalances(overview: ScoreOverview, model: StrengthModel) -> [ImbalanceAnalyzer.Finding] {
        guard let analyzer = try? ImbalanceAnalyzer(params: model.params.imbalance, correlation: model.params.correlation) else { return [] }
        let inputs = overview.exercises.keys.sorted().compactMap { id -> ImbalanceAnalyzer.ScoreInput? in
            guard let evaluation = overview.exercises[id], let exercise = model.exercises[id], let pattern = exercise.movementPattern else { return nil }
            return ImbalanceAnalyzer.ScoreInput(
                exerciseId: id, z: evaluation.score.z, confidence: evaluation.score.confidence, pattern: pattern,
                isMachine: evaluation.score.isMachine, corrKey: exercise.isAnchor ? exercise.anchor?.rawValue : nil,
                muscles: exercise.primaryMuscles
            )
        }
        return (try? analyzer.analyze(inputs)) ?? []
    }

    private func progressFacts(
        overview: ScoreOverview, sets: [String: [ScoredSet]], model: StrengthModel, user: ScoringUser
    ) -> [ExerciseProgressFact] {
        let analyzer = ProgressAnalyzer(params: model.params.progress)
        return overview.exercises.keys.sorted().compactMap { id in
            guard let evaluation = overview.exercises[id], let exercise = model.exercises[id], let history = sets[id] else { return nil }
            let sessions = ScoreService.progressSessions(history, exercise: exercise, model: model, user: user)
            guard sessions.count >= 2 else { return nil }
            let trend = analyzer.trend(sessions)
            let score = analyzer.progressScore(trend, percentile: evaluation.score.score, trainingYears: nil)
            return ExerciseProgressFact(
                exerciseId: id, sessionCount: sessions.count, plateau: analyzer.plateau(sessions).status,
                progressScore: score.status == .ok ? score.score : nil, observedMonthlyPct: score.observedMonthlyPct,
                expectedMonthlyPct: score.expectedMonthlyPct, muscles: exercise.primaryMuscles
            )
        }
    }

    private func repBands(_ sets: [String: [ScoredSet]], today: Int) -> RepBandCounts {
        var bands = RepBandCounts()
        let since = today - Self.repRangeWeeks * 7
        for item in sets.values.joined() where !item.set.isWarmup && item.set.day > since && item.set.day <= today {
            bands.add(reps: item.set.reps)
        }
        return bands
    }

    private func days(from start: Date, to end: Date) -> Int {
        max(0, calendar.dateComponents([.day], from: calendar.startOfDay(for: start), to: calendar.startOfDay(for: end)).day ?? 0)
    }

    // MARK: Storage

    func store(_ candidates: [InsightCandidate], userId: UUID) {
        let context = ModelContext(modelContainer)
        let now = clock()
        var seen = Set<UUID>()
        for candidate in candidates {
            let id = InsightRecord.id(userId: userId, kind: candidate.kind.rawValue, subject: candidate.subject)
            seen.insert(id)
            let priority = (candidate.priority * 100).rounded() / 100
            let payload = candidate.payload.json
            if let record = try? context.fetch(InsightRecord.syncDescriptor(.id(id))).first {
                let changed = !record.isActive || record.deletedAt != nil || record.severityRaw != candidate.severity.rawValue
                    || record.priority != priority || record.payload != payload || record.actionRaw != candidate.action.rawValue
                guard changed else { continue }
                if !record.isActive || record.deletedAt != nil { record.detectedAt = now }
                record.isActive = true
                record.deletedAt = nil
                record.severityRaw = candidate.severity.rawValue
                record.priority = priority
                record.payload = payload
                record.actionRaw = candidate.action.rawValue
                record.markPending(at: now)
            } else {
                context.insert(InsightRecord(
                    userId: userId, kind: candidate.kind, subject: candidate.subject, severity: candidate.severity, priority: priority,
                    action: candidate.action, payload: candidate.payload, detectedAt: now, now: now
                ))
            }
        }
        for record in (try? context.fetch(InsightRecord.syncDescriptor(.user(userId)))) ?? [] where record.isActive && !seen.contains(record.id) {
            record.isActive = false
            record.markPending(at: now)
        }
        try? context.save()
    }
}

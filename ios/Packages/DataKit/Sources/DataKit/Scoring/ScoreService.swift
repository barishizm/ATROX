import Foundation
import StrengthKit
import SwiftData

public enum ScoreUnavailable: Error, Sendable, Equatable {
    case noProfile, noBodyweight, noModel
}

public enum ScoreOutcome: Sendable, Equatable {
    case ready(ScoreOverview)
    case unavailable(ScoreUnavailable)
}

/// What triggered a recalculation.
public enum ScoreTrigger: Sendable, Equatable {
    /// A workout finished or history changed: only these catalog exercises changed.
    case exercises(Set<String>)
    /// Weight, profile, reference group or model version changed: everything.
    case everything
}

/// Keeps scores current and writes `ScoreSnapshot`s (P064). All reads and writes use fresh `ModelContext`s on this
/// actor, so the UI never waits for scoring. Incremental runs recompute only the affected exercises and re-aggregate
/// the muscle and overall scores from the cached evaluations; the result equals a full recalculation.
public actor ScoreService {
    /// A snapshot is written when the score moved by at least this much, the model changed, or the last one is a week old.
    public static let meaningfulChange = 0.5
    public static let snapshotIntervalDays = 7
    public static let backfillWeeks = 104

    private let modelContainer: ModelContainer
    private let scoringModel: @Sendable () async -> ScoringModel?
    private let clock: @Sendable () -> Date
    private let calendar: Calendar
    private var cache: [CacheKey: Cached] = [:]

    private struct CacheKey: Hashable {
        var userId: UUID
        var population: ReferencePopulation
    }

    private struct Cached {
        var asOfDay: Int
        var modelVersion: String
        var user: ScoringUser
        var overview: ScoreOverview
        var sets: [String: [ScoredSet]]
    }

    public init(
        modelContainer: ModelContainer, scoringModel: @escaping @Sendable () async -> ScoringModel?,
        clock: @escaping @Sendable () -> Date = { Date() }, calendar: Calendar = .current
    ) {
        self.modelContainer = modelContainer
        self.scoringModel = scoringModel
        self.clock = clock
        self.calendar = calendar
    }

    // MARK: Public API

    /// The reference group the user picked in settings (gym by default).
    public func preferredPopulation(userId: UUID) -> ReferencePopulation {
        let context = ModelContext(modelContainer)
        let settings = try? context.fetch(UserSettings.syncDescriptor(.user(userId))).first
        return settings?.referenceGroup == .general ? .general : .gym
    }

    /// Current scores of one reference group, computed if not cached. No snapshots are written.
    public func overview(userId: UUID, population: ReferencePopulation? = nil) async -> ScoreOutcome {
        let group = population ?? preferredPopulation(userId: userId)
        return await compute(userId: userId, population: group, trigger: .everything, persist: false)
    }

    /// Recomputes after a change and stores snapshots. Returns the new overview of the preferred reference group.
    @discardableResult
    public func recalculate(userId: UUID, trigger: ScoreTrigger) async -> ScoreOutcome {
        await compute(userId: userId, population: preferredPopulation(userId: userId), trigger: trigger, persist: true)
    }

    /// One exercise under any reference group, straight from the history (instant group switcher, no storage).
    public func evaluation(userId: UUID, exerciseId: String, population: ReferencePopulation) async -> ExerciseEvaluation? {
        guard let model = await scoringModel(), case .success(let user) = scoringUser(userId: userId, on: clock()) else { return nil }
        let id = ScoreCalculator.scoringId(exerciseId)
        let sets = (try? loadSets(userId: userId, exerciseIds: [id])) ?? [:]
        return ScoreCalculator.evaluate(
            id, sets: sets[id] ?? [], model: model.model, user: user, population: population, asOfDay: ScoreCalculator.dayNumber(clock(), calendar: calendar)
        )
    }

    public func bodyweight(userId: UUID) -> BodyweightStatus? {
        let context = ModelContext(modelContainer)
        return bodyweightStatus(context: context, userId: userId, now: clock())
    }

    /// Score series of one scope/key for charts, oldest first.
    public func history(userId: UUID, scope: SnapshotScope, key: String, population: ReferencePopulation) -> [(date: Date, score: Double)] {
        let context = ModelContext(modelContainer)
        let scopeRaw = scope.rawValue, group = population.rawValue
        let descriptor = FetchDescriptor<ScoreSnapshot>(
            predicate: #Predicate {
                $0.userId == userId && $0.deletedAt == nil && $0.scopeRaw == scopeRaw && $0.key == key && $0.referenceGroupRaw == group
            },
            sortBy: [SortDescriptor(\.date)]
        )
        return ((try? context.fetch(descriptor)) ?? []).map { ($0.date, $0.score) }
    }

    /// First install: weekly snapshots for the existing history. No-op when snapshots already exist.
    public func backfillIfNeeded(userId: UUID) async {
        let context = ModelContext(modelContainer)
        var probe = ScoreSnapshot.syncDescriptor(.user(userId))
        probe.fetchLimit = 1
        guard (try? context.fetch(probe))?.isEmpty ?? true, let model = await scoringModel() else { return }
        let population = preferredPopulation(userId: userId)
        guard let sets = try? loadSets(userId: userId, exerciseIds: nil), !sets.isEmpty else { return }
        let firstDay = sets.values.flatMap { $0 }.map(\.set.day).min() ?? 0
        let today = ScoreCalculator.dayNumber(clock(), calendar: calendar)
        let startDay = max(firstDay, today - Self.backfillWeeks * 7)
        var day = today
        var days: [Int] = []
        while day >= startDay {
            days.append(day)
            day -= Self.snapshotIntervalDays
        }
        guard let profile = profileFacts(context: context, userId: userId), let weight = bodyweightStatus(context: context, userId: userId, now: clock()) else {
            return
        }
        for asOf in days.reversed() {
            let date = date(ofDay: asOf)
            let user = ScoringUser(sex: profile.sex, age: Double(max(1, ScoreCalculator.age(birthDate: profile.birthDate, on: date, calendar: calendar))), bodyweightKg: weight.weightKg)
            let visible = sets.mapValues { $0.filter { $0.set.day <= asOf } }.filter { !$0.value.isEmpty }
            let overview = ScoreCalculator.compute(sets: visible, scoring: model, user: user, population: population, asOfDay: asOf)
            store(overview, userId: userId, date: date, context: context, force: true)
        }
        try? context.save()
    }

    /// Drops cached results (sign-out, account switch).
    public func reset() { cache = [:] }

    // MARK: Computation

    /// Looks for score-relevant changes (history, weight, profile, settings, model version) since the last run and
    /// recomputes what they touch. nil when nothing changed. Cheap to call after every local save: it loads the
    /// finished sets once and diffs them per exercise.
    @discardableResult
    public func refresh(userId: UUID) async -> ScoreOutcome? {
        guard let loaded = try? loadSets(userId: userId, exerciseIds: nil) else { return nil }
        let population = preferredPopulation(userId: userId)
        guard let scoring = await scoringModel() else { return nil }
        if case .success(let user) = scoringUser(userId: userId, on: clock()),
           let cached = cache[CacheKey(userId: userId, population: population)],
           cached.asOfDay == ScoreCalculator.dayNumber(clock(), calendar: calendar), cached.modelVersion == scoring.version,
           cached.user == user {
            let changed = Set(loaded.keys).union(cached.sets.keys).filter { loaded[$0] != cached.sets[$0] }
            if changed.isEmpty { return nil }
            return await compute(userId: userId, population: population, trigger: .exercises(changed), persist: true, preloaded: loaded)
        }
        return await compute(userId: userId, population: population, trigger: .everything, persist: true, preloaded: loaded)
    }

    private func compute(
        userId: UUID, population: ReferencePopulation, trigger: ScoreTrigger, persist: Bool, preloaded: [String: [ScoredSet]]? = nil
    ) async -> ScoreOutcome {
        guard let scoring = await scoringModel() else { return .unavailable(.noModel) }
        let now = clock()
        let user: ScoringUser
        switch scoringUser(userId: userId, on: now) {
        case .failure(let reason): return .unavailable(reason)
        case .success(let value): user = value
        }
        let today = ScoreCalculator.dayNumber(now, calendar: calendar)
        let key = CacheKey(userId: userId, population: population)
        var evaluations: [String: ExerciseEvaluation]
        var allSets: [String: [ScoredSet]]
        let recompute: Set<String>
        do {
            if case .exercises(let changed) = trigger, let cached = cache[key], cached.asOfDay == today,
               cached.modelVersion == scoring.version, cached.user == user {
                let ids = Set(changed.map(ScoreCalculator.scoringId))
                let fresh = try preloaded ?? loadSets(userId: userId, exerciseIds: ids)
                allSets = cached.sets
                for id in ids { allSets[id] = fresh[id] }
                evaluations = cached.overview.exercises
                for id in ids { evaluations[id] = nil }
                recompute = ids
            } else {
                allSets = try preloaded ?? loadSets(userId: userId, exerciseIds: nil)
                evaluations = [:]
                recompute = Set(allSets.keys)
            }
        } catch {
            return .unavailable(.noProfile)
        }
        for id in recompute {
            guard let exerciseSets = allSets[id] else { continue }
            if let value = ScoreCalculator.evaluate(id, sets: exerciseSets, model: scoring.model, user: user, population: population, asOfDay: today) {
                evaluations[id] = value
            }
        }
        let overview = ScoreCalculator.overview(
            evaluations: evaluations, model: scoring.model, version: scoring.version, population: population, asOfDay: today
        )
        cache[key] = Cached(asOfDay: today, modelVersion: scoring.version, user: user, overview: overview, sets: allSets)
        if persist {
            let context = ModelContext(modelContainer)
            store(overview, userId: userId, date: date(ofDay: today), context: context, force: false)
            try? context.save()
        }
        return .ready(overview)
    }

    // MARK: Snapshots

    private struct SnapshotItem {
        var scope: SnapshotScope
        var key: String
        var score: Double
        var z: Double
        var confidence: ScoreConfidence
    }

    private func store(_ overview: ScoreOverview, userId: UUID, date: Date, context: ModelContext, force: Bool) {
        let group = overview.population.rawValue
        var items: [SnapshotItem] = overview.exercises.map {
            SnapshotItem(scope: .exercise, key: $0.key, score: $0.value.score.score, z: $0.value.score.z, confidence: $0.value.score.confidence)
        }
        items += overview.muscles.map {
            SnapshotItem(scope: .muscle, key: $0.key, score: $0.value.score, z: $0.value.z, confidence: $0.value.confidence)
        }
        if let overall = overview.overall {
            items.append(SnapshotItem(scope: .overall, key: "overall", score: overall.score, z: overall.z, confidence: overall.confidence))
        }
        let now = clock()
        for item in items.sorted(by: { ($0.scope.rawValue, $0.key) < ($1.scope.rawValue, $1.key) }) {
            let (scope, key, score, z, confidence) = (item.scope, item.key, item.score, item.z, item.confidence)
            let id = ScoreSnapshot.id(userId: userId, scope: scope.rawValue, key: key, referenceGroup: group, date: date)
            if let existing = try? context.fetch(ScoreSnapshot.syncDescriptor(.id(id))).first {
                guard existing.score != score || existing.modelVersion != overview.modelVersion || existing.deletedAt != nil else { continue }
                existing.score = score
                existing.z = z
                existing.confidenceRaw = confidence.rawValue
                existing.modelVersion = overview.modelVersion
                existing.deletedAt = nil
                existing.markPending(at: now)
            } else if force || isMeaningful(score: score, version: overview.modelVersion, before: date, userId: userId, scope: scope, key: key, group: group, context: context) {
                context.insert(
                    ScoreSnapshot(
                        userId: userId, scope: scope, key: key, referenceGroup: group, score: score, z: z,
                        confidence: confidence.rawValue, modelVersion: overview.modelVersion, date: date, now: now
                    )
                )
            }
        }
    }

    private func isMeaningful(
        score: Double, version: String, before date: Date, userId: UUID, scope: SnapshotScope, key: String, group: String, context: ModelContext
    ) -> Bool {
        let scopeRaw = scope.rawValue
        var descriptor = FetchDescriptor<ScoreSnapshot>(
            predicate: #Predicate {
                $0.userId == userId && $0.deletedAt == nil && $0.scopeRaw == scopeRaw && $0.key == key
                    && $0.referenceGroupRaw == group && $0.date < date
            },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        guard let last = (try? context.fetch(descriptor))?.first else { return true }
        let days = calendar.dateComponents([.day], from: last.date, to: date).day ?? 0
        return abs(last.score - score) >= Self.meaningfulChange || last.modelVersion != version || days >= Self.snapshotIntervalDays
    }

    private func date(ofDay day: Int) -> Date { ScoreCalculator.date(ofDay: day, calendar: calendar) }

    // MARK: Inputs (shared with `ExerciseInsight`)

    func currentScoringModel() async -> ScoringModel? { await scoringModel() }
    func currentDate() -> Date { clock() }
    var currentCalendar: Calendar { calendar }
    func currentUser(userId: UUID) -> Result<ScoringUser, ScoreUnavailable> { scoringUser(userId: userId, on: clock()) }
    func loadScoredSets(userId: UUID, exerciseIds: Set<String>?) throws -> [String: [ScoredSet]] {
        try loadSets(userId: userId, exerciseIds: exerciseIds)
    }

    private struct ProfileFacts {
        var sex: ModelSex?
        var birthDate: Date
    }

    private func profileFacts(context: ModelContext, userId: UUID) -> ProfileFacts? {
        guard let profile = try? context.fetch(UserProfile.syncDescriptor(.user(userId))).first(where: { $0.deletedAt == nil }) else { return nil }
        let sex: ModelSex? = switch profile.sex {
        case .male: .male
        case .female: .female
        case .unspecified: nil
        }
        return ProfileFacts(sex: sex, birthDate: profile.birthDate)
    }

    private func bodyweightStatus(context: ModelContext, userId: UUID, now: Date) -> BodyweightStatus? {
        var descriptor = FetchDescriptor<BodyMeasurement>(
            predicate: #Predicate { $0.userId == userId && $0.deletedAt == nil }, sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        guard let latest = (try? context.fetch(descriptor))?.first else { return nil }
        return BodyweightStatus(weightKg: latest.weightKg, measuredAt: latest.date, now: now, calendar: calendar)
    }

    private func scoringUser(userId: UUID, on date: Date) -> Result<ScoringUser, ScoreUnavailable> {
        let context = ModelContext(modelContainer)
        guard let profile = profileFacts(context: context, userId: userId) else { return .failure(.noProfile) }
        guard let weight = bodyweightStatus(context: context, userId: userId, now: date) else { return .failure(.noBodyweight) }
        let age = ScoreCalculator.age(birthDate: profile.birthDate, on: date, calendar: calendar)
        guard age > 0 else { return .failure(.noProfile) }
        return .success(ScoringUser(sex: profile.sex, age: Double(age), bodyweightKg: weight.weightKg))
    }

    /// Completed, non-deleted working and warm-up sets of finished workouts, grouped by scored exercise id.
    /// `exerciseIds == nil` loads the whole history.
    private func loadSets(userId: UUID, exerciseIds: Set<String>?) throws -> [String: [ScoredSet]] {
        let context = ModelContext(modelContainer)
        let sourceIds = exerciseIds.map { Set($0.flatMap(ScoreCalculator.sourceIds(of:))) }
        let exercises = try context.fetch(
            FetchDescriptor<WorkoutExercise>(predicate: #Predicate { $0.userId == userId && $0.deletedAt == nil && $0.exerciseId != nil })
        ).filter { row in row.exerciseId.map { sourceIds?.contains($0) ?? true } ?? false }
        guard !exercises.isEmpty else { return [:] }
        let workoutIds = Set(exercises.map(\.workoutId))
        let workouts = try context.fetch(
            FetchDescriptor<Workout>(predicate: #Predicate { workoutIds.contains($0.id) && $0.deletedAt == nil && $0.endedAt != nil })
        )
        let starts = Dictionary(uniqueKeysWithValues: workouts.map { ($0.id, $0.startedAt) })
        let live = exercises.filter { starts[$0.workoutId] != nil }
        let rowIds = Set(live.map(\.id))
        let entries = try context.fetch(
            FetchDescriptor<SetEntry>(predicate: #Predicate { rowIds.contains($0.workoutExerciseId) && $0.deletedAt == nil && $0.isCompleted })
        )
        let parents = Dictionary(uniqueKeysWithValues: live.map { ($0.id, $0) })
        var out: [String: [ScoredSet]] = [:]
        for entry in entries.sorted(by: { ($0.workoutExerciseId.uuidString, $0.position) < ($1.workoutExerciseId.uuidString, $1.position) }) {
            guard entry.reps >= 1, entry.weightKg >= 0, let parent = parents[entry.workoutExerciseId],
                  let started = starts[parent.workoutId], let rawId = parent.exerciseId else { continue }
            let set = ScoringSet(
                day: ScoreCalculator.dayNumber(started, calendar: calendar), weightKg: entry.weightKg, reps: entry.reps,
                rir: entry.rir.map(Double.init), isWarmup: entry.setType == .warmup
            )
            out[ScoreCalculator.scoringId(rawId), default: []].append(ScoredSet(setId: entry.id, set: set))
        }
        return out
    }
}

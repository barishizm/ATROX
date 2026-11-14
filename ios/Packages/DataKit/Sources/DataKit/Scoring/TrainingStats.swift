import Foundation
import StrengthKit
import SwiftData

/// Weighted set volume per muscle for the muscle views (P066).
public struct MuscleReport: Sendable, Equatable {
    /// Last 7 days (today included).
    public var last7Days: [String: Double]
    /// Four rolling weeks, oldest first.
    public var weekly: [String: [Double]]

    public init(last7Days: [String: Double], weekly: [String: [Double]]) {
        self.last7Days = last7Days
        self.weekly = weekly
    }
}

/// Finished workout count and the newest one.
public struct ActivitySummary: Sendable, Equatable {
    public var finishedWorkouts: Int
    public var lastWorkoutAt: Date?

    public init(finishedWorkouts: Int, lastWorkoutAt: Date?) {
        self.finishedWorkouts = finishedWorkouts
        self.lastWorkoutAt = lastWorkoutAt
    }
}

public struct RecordHighlight: Sendable, Equatable {
    public var exerciseId: String
    public var kind: RecordKind
    public var value: Double
    public var date: Date

    public init(exerciseId: String, kind: RecordKind, value: Double, date: Date) {
        self.exerciseId = exerciseId
        self.kind = kind
        self.value = value
        self.date = date
    }
}

/// Facts the Today dashboard needs besides the scores (P067).
public struct DashboardFacts: Sendable, Equatable {
    public var workoutsThisWeek: Int
    public var streakWeeks: Int
    public var finishedWorkouts: Int
    public var trainedToday: Bool
    public var lastRecord: RecordHighlight?
    public var mostImproved: (exerciseId: String, change: Double)?
    public var overallChange: Double?
    /// Weekly workout goal behind the streak and the goal ring.
    public var goal: Int

    public static func == (lhs: DashboardFacts, rhs: DashboardFacts) -> Bool {
        lhs.workoutsThisWeek == rhs.workoutsThisWeek && lhs.streakWeeks == rhs.streakWeeks
            && lhs.finishedWorkouts == rhs.finishedWorkouts && lhs.trainedToday == rhs.trainedToday
            && lhs.lastRecord == rhs.lastRecord
            && lhs.mostImproved?.exerciseId == rhs.mostImproved?.exerciseId && lhs.mostImproved?.change == rhs.mostImproved?.change
            && lhs.overallChange == rhs.overallChange && lhs.goal == rhs.goal
    }
}

/// Reads training history for the Analysis and Today tabs. Every call uses a fresh `ModelContext`, so results are
/// current after edits made elsewhere and nothing is held between calls.
public actor TrainingStats {
    public static let streakLookbackWeeks = 52
    public static let changeDays = 30
    public static let muscleChangeDays = 28

    let modelContainer: ModelContainer
    let clock: @Sendable () -> Date
    let calendar: Calendar

    public init(modelContainer: ModelContainer, clock: @escaping @Sendable () -> Date = { Date() }, calendar: Calendar = .current) {
        self.modelContainer = modelContainer
        self.clock = clock
        self.calendar = calendar
    }

    // MARK: Muscles

    public func muscleReport(userId: UUID) -> MuscleReport {
        let context = ModelContext(modelContainer)
        let today = ScoreCalculator.dayNumber(clock(), calendar: calendar)
        let entries = volumeEntries(context: context, userId: userId, sinceDay: today - 27)
        let roles = muscleRoles(context: context)
        return MuscleReport(
            last7Days: MuscleVolume.sets(entries, roles: roles, days: (today - 6)...today),
            weekly: MuscleVolume.weekly(entries, roles: roles, endDay: today)
        )
    }

    /// Score change of every muscle over the last four weeks (muscles without enough history are absent).
    public func muscleChanges(userId: UUID, population: ReferencePopulation) -> [String: Double] {
        let context = ModelContext(modelContainer)
        let now = clock()
        let series = snapshotSeries(context: context, userId: userId, scope: .muscle, population: population, days: Self.muscleChangeDays + 7)
        return series.compactMapValues { ScoreTrend.change($0, now: now, days: Self.muscleChangeDays, calendar: calendar) }
    }

    // MARK: Dashboard

    /// `goal` overrides the weekly workout goal of the profile (e.g. the number of planned weekdays).
    public func dashboard(userId: UUID, population: ReferencePopulation, overallScore: Double?, goal override: Int? = nil) -> DashboardFacts {
        let context = ModelContext(modelContainer)
        let now = clock()
        let workouts = finishedWorkouts(context: context, userId: userId)
        let goal = max(1, override ?? profileGoal(context: context, userId: userId))
        let counts = WeeklyActivity.counts(workouts.map(\.startedAt), now: now, weeks: Self.streakLookbackWeeks, calendar: calendar)
        let startOfToday = calendar.startOfDay(for: now)
        let overall = snapshotSeries(context: context, userId: userId, scope: .overall, population: population, days: Self.changeDays + 7)["overall"]
        let exerciseSeries = snapshotSeries(context: context, userId: userId, scope: .exercise, population: population, days: Self.changeDays + 7)
        return DashboardFacts(
            workoutsThisWeek: counts.last ?? 0, streakWeeks: WeeklyActivity.streak(counts: counts, goal: goal),
            finishedWorkouts: workouts.count, trainedToday: workouts.contains { $0.startedAt >= startOfToday },
            lastRecord: lastRecord(context: context, userId: userId),
            mostImproved: ScoreTrend.mostImproved(exerciseSeries, now: now, days: Self.changeDays, calendar: calendar)
                .map { (exerciseId: $0.key, change: $0.change) },
            overallChange: overall.flatMap { ScoreTrend.change($0, current: overallScore, now: now, days: Self.changeDays, calendar: calendar) },
            goal: goal
        )
    }

    /// The routine day trained last within one routine.
    public func lastRoutineDayId(userId: UUID, routineId: UUID) -> UUID? {
        let context = ModelContext(modelContainer)
        return finishedWorkouts(context: context, userId: userId).first { $0.routineId == routineId && $0.routineDayId != nil }?.routineDayId
    }

    // MARK: Progress charts (P068)

    /// `weeks` consecutive 7-day volume windows ending today, oldest first.
    public func weeklyVolume(userId: UUID, weeks: Int) -> [WeekVolume] {
        let context = ModelContext(modelContainer)
        let today = ScoreCalculator.dayNumber(clock(), calendar: calendar)
        let entries = volumeEntries(context: context, userId: userId, sinceDay: today - 7 * weeks + 1)
        return VolumeSeries.weekly(entries, roles: muscleRoles(context: context), endDay: today, weeks: weeks, calendar: calendar)
    }

    /// Finished workouts per day number over the whole history (the calendar view picks its six months).
    public func workoutCalendar(userId: UUID) -> [Int: Int] {
        let context = ModelContext(modelContainer)
        return FrequencyCalendar.perDay(finishedWorkouts(context: context, userId: userId).map(\.startedAt), calendar: calendar)
    }

    public func bodyweightHistory(userId: UUID) -> [BodyweightPoint] {
        let context = ModelContext(modelContainer)
        let rows = (try? context.fetch(FetchDescriptor<BodyMeasurement>(
            predicate: #Predicate { $0.userId == userId && $0.deletedAt == nil }, sortBy: [SortDescriptor(\.date)]
        ))) ?? []
        return rows.map { BodyweightPoint(day: ScoreCalculator.dayNumber($0.date, calendar: calendar), date: $0.date, weightKg: $0.weightKg) }
    }

    /// How much the user has trained and when last (insight rules).
    public func activity(userId: UUID) -> ActivitySummary {
        let context = ModelContext(modelContainer)
        let workouts = finishedWorkouts(context: context, userId: userId)
        return ActivitySummary(finishedWorkouts: workouts.count, lastWorkoutAt: workouts.first?.startedAt)
    }

    // MARK: Queries

    struct FinishedWorkout {
        var id: UUID
        var startedAt: Date
        var routineId: UUID?
        var routineDayId: UUID?
    }

    /// Finished, non-deleted workouts, newest first.
    func finishedWorkouts(context: ModelContext, userId: UUID) -> [FinishedWorkout] {
        let rows = (try? context.fetch(FetchDescriptor<Workout>(
            predicate: #Predicate { $0.userId == userId && $0.deletedAt == nil && $0.endedAt != nil }, sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        ))) ?? []
        return rows.map { FinishedWorkout(id: $0.id, startedAt: $0.startedAt, routineId: $0.routineId, routineDayId: $0.routineDayId) }
    }

    /// Completed working sets (warm-ups excluded) of catalog exercises per workout day and exercise.
    func volumeEntries(context: ModelContext, userId: UUID, sinceDay: Int) -> [VolumeEntry] {
        let since = ScoreCalculator.date(ofDay: sinceDay - 1, calendar: calendar)
        let workouts = (try? context.fetch(FetchDescriptor<Workout>(
            predicate: #Predicate { $0.userId == userId && $0.deletedAt == nil && $0.endedAt != nil && $0.startedAt >= since }
        ))) ?? []
        guard !workouts.isEmpty else { return [] }
        let days = Dictionary(uniqueKeysWithValues: workouts.map { ($0.id, ScoreCalculator.dayNumber($0.startedAt, calendar: calendar)) })
        let workoutIds = Set(days.keys)
        let exercises = ((try? context.fetch(FetchDescriptor<WorkoutExercise>(
            predicate: #Predicate { $0.userId == userId && $0.deletedAt == nil && $0.exerciseId != nil }
        ))) ?? []).filter { workoutIds.contains($0.workoutId) }
        guard !exercises.isEmpty else { return [] }
        let rowIds = Set(exercises.map(\.id))
        let sets = (try? context.fetch(FetchDescriptor<SetEntry>(
            predicate: #Predicate { rowIds.contains($0.workoutExerciseId) && $0.deletedAt == nil && $0.isCompleted }
        ))) ?? []
        var counts: [UUID: Int] = [:]
        for set in sets where set.setType != .warmup { counts[set.workoutExerciseId, default: 0] += 1 }
        var merged: [String: VolumeEntry] = [:]
        for row in exercises {
            guard let exerciseId = row.exerciseId, let day = days[row.workoutId], let count = counts[row.id] else { continue }
            let key = "\(day)|\(exerciseId)"
            merged[key, default: VolumeEntry(day: day, exerciseId: exerciseId, sets: 0)].sets += count
        }
        return merged.keys.sorted().compactMap { merged[$0] }
    }

    func muscleRoles(context: ModelContext) -> [String: MuscleRoles] {
        var out: [String: MuscleRoles] = [:]
        for exercise in (try? context.fetch(FetchDescriptor<Exercise>())) ?? [] {
            out[exercise.id] = MuscleRoles(primary: exercise.primaryMuscles, secondary: exercise.secondaryMuscles)
        }
        return out
    }

    func profileGoal(context: ModelContext, userId: UUID) -> Int {
        ((try? context.fetch(UserProfile.syncDescriptor(.user(userId)))) ?? []).first { $0.deletedAt == nil }?.weeklyFrequency ?? 3
    }

    private func lastRecord(context: ModelContext, userId: UUID) -> RecordHighlight? {
        var descriptor = FetchDescriptor<PersonalRecord>(
            predicate: #Predicate { $0.userId == userId && $0.deletedAt == nil && $0.exerciseId != nil }, sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        guard let row = (try? context.fetch(descriptor))?.first, let id = row.exerciseId else { return nil }
        return RecordHighlight(exerciseId: id, kind: row.kind, value: row.value, date: row.date)
    }

    /// Score series per key over the last `days` days plus one older point to compare against.
    func snapshotSeries(
        context: ModelContext, userId: UUID, scope: SnapshotScope, population: ReferencePopulation, days: Int
    ) -> [String: [ScorePoint]] {
        let scopeRaw = scope.rawValue, group = population.rawValue
        let rows = (try? context.fetch(FetchDescriptor<ScoreSnapshot>(
            predicate: #Predicate { $0.userId == userId && $0.deletedAt == nil && $0.scopeRaw == scopeRaw && $0.referenceGroupRaw == group },
            sortBy: [SortDescriptor(\.date)]
        ))) ?? []
        var out: [String: [ScorePoint]] = [:]
        for row in rows { out[row.key, default: []].append(ScorePoint(date: row.date, score: row.score)) }
        // Keep the points inside the window and the newest one before it (the comparison base).
        let cutoff = calendar.date(byAdding: .day, value: -days, to: clock()) ?? .distantPast
        return out.mapValues { points in
            let older = points.last { $0.date < cutoff }
            return (older.map { [$0] } ?? []) + points.filter { $0.date >= cutoff }
        }
    }
}

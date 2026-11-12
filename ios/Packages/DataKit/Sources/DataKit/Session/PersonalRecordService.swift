import Foundation
import StrengthKit
import SwiftData

/// Stored personal records (P040). Detection while training is incremental: a completed set is compared with the
/// stored records only. A full replay of one exercise's history runs when the exercise has no records yet (first
/// entry, or history that predates this engine) and whenever history changes (`exerciseChanged`: edit, un-complete,
/// delete). Replays are scoped to a single exercise, never the whole log.
///
/// Every public call works in a fresh `ModelContext`: the workout repository writes through its own context, and a
/// long-lived one here would keep serving stale rows after an edit or delete made elsewhere.
public actor SwiftDataPersonalRecordService: PersonalRecordDetecting {
    private let modelContainer: ModelContainer
    private let clock: @Sendable () -> Date
    private var modelContext: ModelContext

    public init(modelContainer: ModelContainer, clock: @escaping @Sendable () -> Date = { Date() }) {
        self.modelContainer = modelContainer
        self.clock = clock
        modelContext = ModelContext(modelContainer)
    }

    // MARK: PersonalRecordDetecting

    public func records(
        for set: SetSnapshot, ref: ExerciseRef, userId: UUID, workoutId: UUID
    ) throws -> [PersonalRecordHit] {
        guard set.input.countsForScore else { return [] }
        modelContext = ModelContext(modelContainer)
        let rows = try liveRows(userId: userId, ref: ref)
        let found: [RecordBreak]
        if rows.isEmpty || rows.contains(where: { $0.setId == set.id }) {
            found = try replay(userId: userId, ref: ref).breaks[set.id] ?? []
        } else {
            let date = try startedAt(workoutId: workoutId) ?? clock()
            let candidate = RecordSet(
                id: set.id, date: date, order: Int.max, weightKg: set.input.weightKg, reps: set.input.reps,
                rir: set.input.rir
            )
            let board = try marks(of: rows)
            found = RecordMath.breaks(candidate, against: board)
            try reconcile(rows, with: RecordMath.updated(board, with: candidate), userId: userId, ref: ref)
            try modelContext.save()
        }
        return found.map { hit in
            PersonalRecordHit(
                ref: ref, kind: RecordKind(rawValue: hit.metric.rawValue) ?? .weight, value: hit.value, setId: set.id,
                previousValue: hit.previousValue, needsConfirmation: hit.isOutlier
            )
        }
    }

    // `async` on purpose: with a sync signature callers would resolve to the protocol's no-op default instead.
    public func exerciseChanged(ref: ExerciseRef, userId: UUID) async throws {
        modelContext = ModelContext(modelContainer)
        _ = try replay(userId: userId, ref: ref)
    }

    /// Standing records of an exercise (for history screens), newest value per kind; reps has one entry per weight.
    public func current(userId: UUID, ref: ExerciseRef) throws -> [RecordMark] {
        modelContext = ModelContext(modelContainer)
        return try marks(of: try liveRows(userId: userId, ref: ref))
    }

    // MARK: Replay

    /// Rebuilds the exercise's records from every completed non-warm-up set and stores the result.
    @discardableResult
    private func replay(userId: UUID, ref: ExerciseRef) throws -> RecordReplay {
        let result = RecordMath.replay(try historySets(userId: userId, ref: ref))
        try reconcile(try liveRows(userId: userId, ref: ref), with: result.board, userId: userId, ref: ref)
        try modelContext.save()
        return result
    }

    private func historySets(userId: UUID, ref: ExerciseRef) throws -> [RecordSet] {
        let exercises = try exerciseRows(userId: userId, ref: ref)
        guard !exercises.isEmpty else { return [] }
        let workoutIds = Set(exercises.map(\.workoutId))
        let workouts = try modelContext.fetch(
            FetchDescriptor<Workout>(predicate: #Predicate { workoutIds.contains($0.id) && $0.deletedAt == nil })
        )
        let starts = Dictionary(uniqueKeysWithValues: workouts.map { ($0.id, $0.startedAt) })
        let live = exercises.filter { starts[$0.workoutId] != nil }
        let exerciseIds = live.map(\.id)
        guard !exerciseIds.isEmpty else { return [] }
        let entries = try modelContext.fetch(
            FetchDescriptor<SetEntry>(
                predicate: #Predicate {
                    exerciseIds.contains($0.workoutExerciseId) && $0.deletedAt == nil && $0.isCompleted
                }
            )
        )
        let parents = Dictionary(uniqueKeysWithValues: live.map { ($0.id, $0) })
        return entries.compactMap { entry -> RecordSet? in
            guard entry.setType != .warmup, entry.reps >= 1, let parent = parents[entry.workoutExerciseId],
                  let date = starts[parent.workoutId]
            else { return nil }
            return RecordSet(
                id: entry.id, date: date, order: parent.position * 1000 + entry.position, weightKg: entry.weightKg,
                reps: entry.reps, rir: entry.rir
            )
        }
    }

    // MARK: Storage

    private func marks(of rows: [PersonalRecord]) throws -> [RecordMark] {
        let setIds = rows.compactMap(\.setId)
        let entries = setIds.isEmpty ? [] : try modelContext.fetch(
            FetchDescriptor<SetEntry>(predicate: #Predicate { setIds.contains($0.id) })
        )
        let weights = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0.weightKg) })
        return rows.compactMap { row in
            guard let metric = RecordMetric(rawValue: row.kindRaw), let setId = row.setId else { return nil }
            return RecordMark(
                metric: metric, value: row.value, setId: setId, date: row.date, weightKg: weights[setId] ?? 0
            )
        }
    }

    /// Makes the stored rows equal `board`: same keys are updated in place, new ones inserted, vanished ones deleted.
    private func reconcile(_ rows: [PersonalRecord], with board: [RecordMark], userId: UUID, ref: ExerciseRef) throws {
        let now = clock()
        var existing: [String: PersonalRecord] = [:]
        for row in rows {
            let key = Self.key(kind: row.kindRaw, setId: row.setId)
            if existing[key] == nil { existing[key] = row } else { row.markDeleted(at: now) }  // duplicate row
        }
        for mark in board {
            let key = Self.key(kind: mark.metric.rawValue, setId: mark.setId)
            if let row = existing.removeValue(forKey: key) {
                if row.value != mark.value || row.setId != mark.setId || row.date != mark.date {
                    row.value = mark.value
                    row.setId = mark.setId
                    row.date = mark.date
                    row.markPending(at: now)
                }
            } else {
                modelContext.insert(
                    PersonalRecord(
                        userId: userId, ref: ref, kind: RecordKind(rawValue: mark.metric.rawValue) ?? .weight,
                        value: mark.value,
                        setId: mark.setId, date: mark.date, now: now
                    )
                )
            }
        }
        for row in existing.values { row.markDeleted(at: now) }  // lost their record
    }

    /// Weight, e1RM and volume have one row each; reps has one row per standing set.
    private static func key(kind: String, setId: UUID?) -> String {
        kind == RecordKind.reps.rawValue ? "reps:\(setId?.uuidString ?? "")" : kind
    }

    private func liveRows(userId: UUID, ref: ExerciseRef) throws -> [PersonalRecord] {
        switch ref {
        case .catalog(let id):
            let target: String? = id
            return try modelContext.fetch(
                FetchDescriptor<PersonalRecord>(
                    predicate: #Predicate { $0.userId == userId && $0.deletedAt == nil && $0.exerciseId == target }
                )
            )
        case .custom(let id):
            let target: UUID? = id
            return try modelContext.fetch(
                FetchDescriptor<PersonalRecord>(
                    predicate: #Predicate {
                        $0.userId == userId && $0.deletedAt == nil && $0.customExerciseId == target
                    }
                )
            )
        }
    }

    private func exerciseRows(userId: UUID, ref: ExerciseRef) throws -> [WorkoutExercise] {
        switch ref {
        case .catalog(let id):
            let target: String? = id
            return try modelContext.fetch(
                FetchDescriptor<WorkoutExercise>(
                    predicate: #Predicate { $0.userId == userId && $0.deletedAt == nil && $0.exerciseId == target }
                )
            )
        case .custom(let id):
            let target: UUID? = id
            return try modelContext.fetch(
                FetchDescriptor<WorkoutExercise>(
                    predicate: #Predicate {
                        $0.userId == userId && $0.deletedAt == nil && $0.customExerciseId == target
                    }
                )
            )
        }
    }

    private func startedAt(workoutId: UUID) throws -> Date? {
        var descriptor = FetchDescriptor<Workout>(predicate: #Predicate { $0.id == workoutId })
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first?.startedAt
    }
}

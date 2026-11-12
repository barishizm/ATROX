import Foundation
import SwiftData

/// The ids of the active workout's tree. Push holds these rows back and pull leaves them alone until the workout
/// ends (docs/02-MIMARI.md §2.4). Records pointing at a held set wait too: the server's foreign key needs the set.
struct SyncLock: Sendable, Equatable {
    var workouts: Set<UUID> = []
    var workoutExercises: Set<UUID> = []
    var sets: Set<UUID> = []
}

/// One row ready to push: what was sent and the local `updatedAt` it was taken at.
struct OutgoingRow: Sendable {
    let id: UUID
    let localUpdatedAt: Date
    let json: JSONObject
}

/// What a pulled page did locally.
struct MergeOutcome: Sendable, Equatable {
    var applied = 0
    var keptLocal = 0
    var skippedLocked = 0
    /// Rows whose earlier failure is moot now that the server version replaced them.
    var resolvedFailures: [UUID] = []
}

/// SwiftData side of the sync engine. A fresh instance (and so a fresh `ModelContext`) is made for every phase, so it
/// reads what the repositories saved in the meantime instead of stale objects.
@ModelActor
actor SyncLocalStore {
    // MARK: Lock

    func lock(userId: UUID) throws -> SyncLock {
        var lock = SyncLock()
        let active = try modelContext.fetch(FetchDescriptor<Workout>(predicate: #Predicate {
            $0.userId == userId && $0.endedAt == nil && $0.deletedAt == nil
        }))
        lock.workouts = Set(active.map(\.id))
        for workoutId in lock.workouts {
            let exercises = try modelContext.fetch(FetchDescriptor<WorkoutExercise>(predicate: #Predicate { $0.workoutId == workoutId }))
            lock.workoutExercises.formUnion(exercises.map(\.id))
        }
        for exerciseId in lock.workoutExercises {
            let sets = try modelContext.fetch(FetchDescriptor<SetEntry>(predicate: #Predicate { $0.workoutExerciseId == exerciseId }))
            lock.sets.formUnion(sets.map(\.id))
        }
        return lock
    }

    // MARK: Push

    /// Pending rows of `table` (plus failed ones when `includeFailed`), minus the locked ones.
    func outgoing(_ table: SyncTable, userId: UUID, lock: SyncLock, includeFailed: Bool) throws -> [OutgoingRow] {
        try outgoing(table.modelType, userId: userId, lock: lock, includeFailed: includeFailed)
    }

    private func outgoing<M: SyncableModel>(
        _ type: M.Type, userId: UUID, lock: SyncLock, includeFailed: Bool
    ) throws -> [OutgoingRow] {
        var models = try modelContext.fetch(M.syncDescriptor(.state(.pending, userId: userId)))
        if includeFailed { models += try modelContext.fetch(M.syncDescriptor(.state(.failed, userId: userId))) }
        return try models.filter { !Self.isLocked($0, lock: lock) }.map {
            OutgoingRow(id: $0.id, localUpdatedAt: $0.updatedAt, json: try SyncCoding.encode($0.makeDTO()))
        }
    }

    /// Marks pushed rows `synced` with the server's `updated_at`, unless the row changed again while the request was
    /// in flight (then it stays pending for the next round).
    func acknowledge(_ table: SyncTable, sent: [OutgoingRow], stored: [JSONObject]) throws {
        try acknowledge(table.modelType, sent: sent, stored: stored)
    }

    private func acknowledge<M: SyncableModel>(_ type: M.Type, sent: [OutgoingRow], stored: [JSONObject]) throws {
        let stamps = Dictionary(stored.compactMap { row in row.rowId.map { ($0, row.rowUpdatedAt) } }, uniquingKeysWith: { $1 })
        for row in sent {
            guard let model = try modelContext.fetch(M.syncDescriptor(.id(row.id))).first,
                  model.updatedAt == row.localUpdatedAt else { continue }
            if let text = stamps[row.id] ?? nil, let serverStamp = SyncTime.parseTimestamp(text) {
                model.updatedAt = serverStamp
            }
            model.syncState = .synced
        }
        try modelContext.save()
    }

    func markFailed(_ table: SyncTable, ids: [UUID]) throws {
        try markFailed(table.modelType, ids: ids)
    }

    private func markFailed<M: SyncableModel>(_ type: M.Type, ids: [UUID]) throws {
        for id in ids {
            try modelContext.fetch(M.syncDescriptor(.id(id))).first?.syncState = .failed
        }
        try modelContext.save()
    }

    // MARK: Pull

    /// Merges server rows into the local store: last writer wins by `updated_at` (the local time shifted by
    /// `clockOffset` onto the server clock), a pending local edit that is newer is kept, a tombstone on either side
    /// wins over an edit, and the active workout's tree is never touched.
    func merge(_ table: SyncTable, rows: [JSONObject], lock: SyncLock, clockOffset: TimeInterval) throws -> MergeOutcome {
        try merge(table.modelType, rows: rows, lock: lock, clockOffset: clockOffset)
    }

    private func merge<M: SyncableModel>(
        _ type: M.Type, rows: [JSONObject], lock: SyncLock, clockOffset: TimeInterval
    ) throws -> MergeOutcome {
        var outcome = MergeOutcome()
        for row in rows {
            let dto = try SyncCoding.decode(M.DTO.self, from: row)
            if Self.isLocked(dto, lock: lock) {
                outcome.skippedLocked += 1
                continue
            }
            guard let local = try modelContext.fetch(M.syncDescriptor(.id(dto.id))).first else {
                modelContext.insert(M(syncDTO: dto))
                outcome.applied += 1
                continue
            }
            if Self.remoteWins(dto, over: local, clockOffset: clockOffset) {
                if local.syncState == .failed { outcome.resolvedFailures.append(local.id) }
                local.apply(dto)
                outcome.applied += 1
            } else {
                outcome.keptLocal += 1
            }
        }
        try modelContext.save()
        return outcome
    }

    static func remoteWins(_ dto: some SyncDTO, over local: some SyncableRecord, clockOffset: TimeInterval) -> Bool {
        guard local.userId == dto.userId else { return false }
        if local.syncState == .synced { return dto.updatedAt > local.updatedAt }
        // Unsent local change (pending or failed): deletions are sticky, otherwise the later write wins.
        let localDeleted = local.deletedAt != nil
        let remoteDeleted = dto.deletedAt != nil
        if remoteDeleted != localDeleted { return remoteDeleted }
        return dto.updatedAt > local.updatedAt.addingTimeInterval(clockOffset)
    }

    // MARK: Status and housekeeping

    func count(_ state: SyncState, userId: UUID) throws -> Int {
        try SyncTable.allCases.reduce(0) { $0 + (try count($1.modelType, state: state, userId: userId)) }
    }

    private func count<M: SyncableModel>(_ type: M.Type, state: SyncState, userId: UUID) throws -> Int {
        try modelContext.fetchCount(M.syncDescriptor(.state(state, userId: userId)))
    }

    /// Deletes every synced row from the device (sign-out, a different account signing in). The catalog stays.
    func wipeAll() throws {
        for table in SyncTable.allCases { try wipe(table.modelType) }
        try modelContext.delete(model: ConsentRecord.self)
        try modelContext.save()
    }

    private func wipe<M: SyncableModel>(_ type: M.Type) throws {
        try modelContext.delete(model: M.self)
    }

    /// Whether the store holds rows of another user (data of an earlier account).
    func hasRows(notOwnedBy userId: UUID) throws -> Bool {
        try SyncTable.allCases.contains { try hasForeignRows($0.modelType, userId: userId) }
    }

    private func hasForeignRows<M: SyncableModel>(_ type: M.Type, userId: UUID) throws -> Bool {
        let all = try modelContext.fetchCount(M.syncDescriptor(.all))
        let own = try modelContext.fetchCount(M.syncDescriptor(.user(userId)))
        return all > own
    }

    // MARK: Locking rules

    private static func isLocked(_ model: some SyncableModel, lock: SyncLock) -> Bool {
        switch model {
        case let workout as Workout: lock.workouts.contains(workout.id)
        case let exercise as WorkoutExercise: lock.workoutExercises.contains(exercise.id)
        case let set as SetEntry: lock.sets.contains(set.id)
        case let record as PersonalRecord: record.setId.map(lock.sets.contains) ?? false
        default: false
        }
    }

    private static func isLocked(_ dto: some SyncDTO, lock: SyncLock) -> Bool {
        switch dto {
        // Another device's unfinished workout is not imported either: a user has one active workout, on one device.
        case let workout as WorkoutDTO:
            lock.workouts.contains(workout.id) || (workout.endedAt == nil && workout.deletedAt == nil)
        case let exercise as WorkoutExerciseDTO:
            lock.workoutExercises.contains(exercise.id) || lock.workouts.contains(exercise.workoutId)
        case let set as SetDTO:
            lock.sets.contains(set.id) || lock.workoutExercises.contains(set.workoutExerciseId)
        default: false
        }
    }
}

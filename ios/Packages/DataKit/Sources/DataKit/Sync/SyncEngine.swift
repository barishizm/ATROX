import Foundation
import SwiftData

/// What one sync pass did.
public struct SyncReport: Sendable, Equatable {
    public var pushed = 0
    public var failed = 0
    public var pulled = 0
    public var keptLocal = 0
    public var skippedLocked = 0

    public init() {}
}

/// Progress of the first full download after sign-in.
public struct SyncProgress: Sendable, Equatable {
    public var done: Int
    public var total: Int

    public var fraction: Double { total == 0 ? 1 : min(1, Double(done) / Double(total)) }

    public init(done: Int, total: Int) {
        self.done = done
        self.total = total
    }
}

/// Offline-first sync of the user's rows with the server (docs/02-MIMARI.md §2.4, P044).
///
/// - **Pull** first, then **push** (so last-writer-wins also holds when this device's pending edit is the older one).
/// - **Push:** pending rows, table by table in dependency order, upserted in chunks. A chunk the server refuses is
///   retried row by row, so one bad row is marked `failed` (with the server's reason) and the rest still land.
///   A transient error stops the pass and leaves everything pending.
/// - **Pull:** per-table keyset paging on the server's `updated_at`, merged by `SyncLocalStore` rules.
/// - The active workout's tree is neither pushed nor overwritten until the workout ends.
public actor SyncEngine {
    public let userId: UUID
    private let container: ModelContainer
    private let remote: any RemoteStore
    public let metadata: SyncMetadataStore
    private let clock: @Sendable () -> Date
    private let chunkSize: Int
    private let pageSize: Int

    public init(
        userId: UUID, modelContainer: ModelContainer, remote: any RemoteStore, metadata: SyncMetadataStore,
        clock: @escaping @Sendable () -> Date = { Date() }, chunkSize: Int = 200, pageSize: Int = 500
    ) {
        self.userId = userId
        container = modelContainer
        self.remote = remote
        self.metadata = metadata
        self.clock = clock
        self.chunkSize = max(1, chunkSize)
        self.pageSize = max(1, pageSize)
    }

    private func local() -> SyncLocalStore { SyncLocalStore(modelContainer: container) }

    // MARK: Passes

    /// Pull, then push. `retryFailed` also resends rows that failed before (the user tapped "sync now").
    @discardableResult
    public func sync(retryFailed: Bool = false) async throws -> SyncReport {
        let offset = try await measureClockOffset()
        // Pull first so a newer edit from another device replaces an older pending one before it would be pushed.
        var report = try await pull(clockOffset: offset, progress: nil)
        let pushed = try await push(retryFailed: retryFailed)
        report.pushed = pushed.pushed
        report.failed = pushed.failed
        await metadata.didSync(at: clock(), clockOffset: offset)
        return report
    }

    /// The first download after sign-in: every table, paged, with progress. Interrupted, it resumes from the stored
    /// cursors on the next call.
    @discardableResult
    public func restore(progress: (@Sendable (SyncProgress) -> Void)? = nil) async throws -> SyncReport {
        let offset = try await measureClockOffset()
        let report = try await pull(clockOffset: offset, progress: progress)
        await metadata.setRestoreCompleted(true)
        await metadata.didSync(at: clock(), clockOffset: offset)
        return report
    }

    public func pendingCount() async throws -> Int { try await local().count(.pending, userId: userId) }
    public func failedCount() async throws -> Int { try await local().count(.failed, userId: userId) }

    // MARK: Push

    public func push(retryFailed: Bool = false) async throws -> SyncReport {
        var report = SyncReport()
        let lock = try await local().lock(userId: userId)
        for table in SyncTable.allCases {
            let rows = try await local().outgoing(table, userId: userId, lock: lock, includeFailed: retryFailed)
            for start in stride(from: 0, to: rows.count, by: chunkSize) {
                let chunk = Array(rows[start..<min(start + chunkSize, rows.count)])
                let result = try await send(table, chunk: chunk)
                report.pushed += result.pushed
                report.failed += result.failed
            }
        }
        return report
    }

    private func send(_ table: SyncTable, chunk: [OutgoingRow]) async throws -> (pushed: Int, failed: Int) {
        do {
            let stored = try await remote.upsert(table: table, rows: chunk.map(\.json))
            try await local().acknowledge(table, sent: chunk, stored: stored)
            await metadata.clearFailures(chunk.map(\.id))
            return (chunk.count, 0)
        } catch RemoteStoreError.permanent where chunk.count > 1 {
            // Find the bad rows: one request per row.
            var pushed = 0
            var failed = 0
            for row in chunk {
                let result = try await send(table, chunk: [row])
                pushed += result.pushed
                failed += result.failed
            }
            return (pushed, failed)
        } catch RemoteStoreError.permanent(let reason) {
            try await local().markFailed(table, ids: chunk.map(\.id))
            for row in chunk { await metadata.recordFailure(id: row.id, reason: reason) }
            return (0, chunk.count)
        }
    }

    // MARK: Pull

    private func pull(clockOffset: TimeInterval, progress: (@Sendable (SyncProgress) -> Void)?) async throws -> SyncReport {
        var report = SyncReport()
        var total = 0
        if progress != nil {
            for table in SyncTable.allCases {
                total += try await remote.countChanges(table: table, after: await metadata.cursor(for: table))
            }
            progress?(SyncProgress(done: 0, total: total))
        }
        var done = 0
        for table in SyncTable.allCases {
            while true {
                let cursor = await metadata.cursor(for: table)
                let rows = try await remote.changes(table: table, after: cursor, limit: pageSize)
                guard let last = rows.last, let lastId = last.rowId, let lastStamp = last.rowUpdatedAt else { break }
                // Lock is re-read per page: the user may start or finish a workout during a long restore.
                let store = local()
                let lock = try await store.lock(userId: userId)
                let outcome = try await store.merge(table, rows: rows, lock: lock, clockOffset: clockOffset)
                await metadata.clearFailures(outcome.resolvedFailures)
                await metadata.setCursor(SyncCursor(updatedAt: lastStamp, id: lastId), for: table)
                report.pulled += outcome.applied
                report.keptLocal += outcome.keptLocal
                report.skippedLocked += outcome.skippedLocked
                done += rows.count
                progress?(SyncProgress(done: done, total: max(total, done)))
                if rows.count < pageSize { break }
            }
        }
        return report
    }

    /// Server clock minus device clock, from the midpoint of the round trip.
    private func measureClockOffset() async throws -> TimeInterval {
        let before = clock()
        let server = try await remote.serverTime()
        let after = clock()
        let midpoint = before.addingTimeInterval(after.timeIntervalSince(before) / 2)
        return server.timeIntervalSince(midpoint)
    }
}

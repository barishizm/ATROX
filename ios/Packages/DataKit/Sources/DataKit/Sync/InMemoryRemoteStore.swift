import Foundation

/// A fake Supabase for tests and previews: PostgREST-like upsert/paging over in-memory tables, with the parts of the
/// real server the engine depends on — RLS by `user_id`, an `updated_at` trigger on the server clock, foreign keys
/// inside the user's data — and switches for going offline or rejecting chosen rows.
public actor InMemoryRemoteStore: RemoteStore {
    private var tables: [SyncTable: [UUID: JSONObject]] = [:]
    private var lastStamp = Date.distantPast
    private var clock: @Sendable () -> Date
    /// The signed-in user; nil means no session.
    public private(set) var userId: UUID?
    public private(set) var isOffline = false
    private var rejected: [UUID: String] = [:]
    /// Number of upsert requests that reached the server (offline calls do not count).
    public private(set) var upsertRequests = 0

    public init(userId: UUID?, clock: @escaping @Sendable () -> Date = { Date() }) {
        self.userId = userId
        self.clock = clock
    }

    // MARK: Test controls

    public func signIn(_ userId: UUID?) { self.userId = userId }
    public func setOffline(_ value: Bool) { isOffline = value }
    public func setClock(_ clock: @escaping @Sendable () -> Date) { self.clock = clock }
    /// Every upsert that contains `id` fails with a constraint-style error.
    public func reject(id: UUID, reason: String = "check constraint violated") { rejected[id] = reason }
    public func accept(id: UUID) { rejected[id] = nil }

    public func row(_ table: SyncTable, id: UUID) -> JSONObject? { tables[table]?[id] }
    public func rows(_ table: SyncTable) -> [JSONObject] { Array(tables[table, default: [:]].values) }
    public func rowCount(_ table: SyncTable) -> Int { tables[table]?.count ?? 0 }

    /// Writes a row as another device would (stamped by the server clock); bypasses the failure switches.
    @discardableResult
    public func seed(_ table: SyncTable, row: JSONObject) -> JSONObject {
        store(table, row: row)
    }

    /// Removes everything of `userId` (what `delete-account` does on the real server).
    public func deleteAll(of userId: UUID) {
        for table in SyncTable.allCases {
            tables[table] = tables[table]?.filter { $0.value.rowUserId != userId }
        }
    }

    // MARK: RemoteStore

    public func upsert(table: SyncTable, rows: [JSONObject]) async throws -> [JSONObject] {
        let user = try session()
        upsertRequests += 1
        for row in rows {
            guard let id = row.rowId else { throw RemoteStoreError.permanent("\(table.rawValue): row without id") }
            if let reason = rejected[id] { throw RemoteStoreError.permanent("\(table.rawValue): \(reason)") }
            guard row.rowUserId == user else { throw RemoteStoreError.permanent("new row violates row-level security policy") }
            if let existing = tables[table]?[id], existing.rowUserId != user {
                throw RemoteStoreError.permanent("new row violates row-level security policy")
            }
            for (column, parent) in table.references {
                guard let value = row[column]?.stringValue else { continue }
                let parentId = UUID(uuidString: value)
                let exists = parentId.map { tables[parent]?[$0]?.rowUserId == user } ?? false
                if !exists { throw RemoteStoreError.permanent("\(table.rawValue).\(column) violates foreign key") }
            }
        }
        return rows.map { store(table, row: $0) }
    }

    public func changes(table: SyncTable, after cursor: SyncCursor?, limit: Int) async throws -> [JSONObject] {
        Array(try visible(table, after: cursor).prefix(limit))
    }

    public func countChanges(table: SyncTable, after cursor: SyncCursor?) async throws -> Int {
        try visible(table, after: cursor).count
    }

    public func serverTime() async throws -> Date {
        if isOffline { throw RemoteStoreError.transient("offline") }
        return clock()
    }

    // MARK: Plumbing

    private func session() throws -> UUID {
        if isOffline { throw RemoteStoreError.transient("offline") }
        guard let userId else { throw RemoteStoreError.unauthorized }
        return userId
    }

    private struct RowKey: Comparable {
        let stamp: Date
        let id: String

        static func < (lhs: RowKey, rhs: RowKey) -> Bool {
            lhs.stamp != rhs.stamp ? lhs.stamp < rhs.stamp : lhs.id < rhs.id
        }
    }

    private func visible(_ table: SyncTable, after cursor: SyncCursor?) throws -> [JSONObject] {
        let user = try session()
        let floor: RowKey? = cursor.map {
            RowKey(stamp: SyncTime.parseTimestamp($0.updatedAt) ?? .distantPast, id: $0.id.uuidString)
        }
        var keyed: [(key: RowKey, row: JSONObject)] = []
        for row in tables[table, default: [:]].values where row.rowUserId == user {
            let key = Self.key(row)
            if let floor, !(floor < key) { continue }
            keyed.append((key, row))
        }
        keyed.sort { $0.key < $1.key }
        return keyed.map(\.row)
    }

    private static func key(_ row: JSONObject) -> RowKey {
        RowKey(stamp: row.rowUpdatedAt.flatMap(SyncTime.parseTimestamp) ?? .distantPast, id: row.rowId?.uuidString ?? "")
    }

    /// The `set_updated_at` trigger: every write gets a fresh, strictly increasing server timestamp.
    private func store(_ table: SyncTable, row: JSONObject) -> JSONObject {
        var stamp = clock()
        if stamp <= lastStamp { stamp = lastStamp.addingTimeInterval(0.000_0015) }
        let text = SyncTime.timestamp(stamp)
        lastStamp = SyncTime.parseTimestamp(text) ?? stamp
        var stored = row
        stored["updated_at"] = .string(text)
        if let id = row.rowId {
            if let created = tables[table]?[id]?["created_at"] { stored["created_at"] = created }
            tables[table, default: [:]][id] = stored
        }
        return stored
    }
}

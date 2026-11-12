import Foundation

/// Where the pull of one table stopped: the server's `updated_at` text of the last row seen (kept verbatim so no
/// precision is lost) and that row's id as the tie-breaker. Keyset paging: the next page is `(updated_at, id) > cursor`.
public struct SyncCursor: Sendable, Codable, Hashable {
    public var updatedAt: String
    public var id: UUID

    public init(updatedAt: String, id: UUID) {
        self.updatedAt = updatedAt
        self.id = id
    }
}

public enum RemoteStoreError: Error, Equatable, Sendable {
    /// Network down, timeout, 5xx, rate limit: try again later, keep the rows pending.
    case transient(String)
    /// The server refused the rows (constraint, RLS, bad value): retrying the same data will fail again.
    case permanent(String)
    /// No signed-in session (or it expired and could not be refreshed).
    case unauthorized

    public var reason: String {
        switch self {
        case .transient(let text), .permanent(let text): text
        case .unauthorized: "unauthorized"
        }
    }
}

/// The server side of the sync engine (docs/02-MIMARI.md §2.4). Every call acts as the signed-in user, so RLS limits
/// it to that user's rows. `SupabaseRemoteStore` is the production one; `InMemoryRemoteStore` the test server.
public protocol RemoteStore: Sendable {
    /// Inserts or updates `rows` by `id` in one request (all or nothing) and returns them as stored, with the server's
    /// `updated_at`.
    func upsert(table: SyncTable, rows: [JSONObject]) async throws -> [JSONObject]
    /// Rows of `table` changed after `cursor` (all rows when nil), oldest first, at most `limit`.
    func changes(table: SyncTable, after cursor: SyncCursor?, limit: Int) async throws -> [JSONObject]
    /// How many rows `changes` would return in total; used for the first-restore progress bar.
    func countChanges(table: SyncTable, after cursor: SyncCursor?) async throws -> Int
    /// The server's clock, to measure how far the device clock is off.
    func serverTime() async throws -> Date
}

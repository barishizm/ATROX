import Foundation

/// Sync bookkeeping that is not part of any row: pull cursors, why rows failed, the last successful sync, whose data
/// the local store holds and whether the first restore finished. Kept in a small JSON file (or only in memory).
public actor SyncMetadataStore {
    public struct State: Codable, Equatable, Sendable {
        /// The user whose rows the local store holds; a different user signing in means the store must be wiped.
        public var ownerUserId: UUID?
        public var cursors: [String: SyncCursor] = [:]
        /// Row id → server message, for rows marked `failed`.
        public var failures: [UUID: String] = [:]
        public var lastSyncedAt: Date?
        /// Server clock minus device clock, measured on the last sync.
        public var clockOffset: TimeInterval = 0
        /// The first full pull after sign-in completed (an interrupted one resumes from the cursors).
        public var restoreCompleted = false
    }

    private var state: State
    private let fileURL: URL?

    /// `fileURL` nil keeps everything in memory (tests).
    public init(fileURL: URL? = nil) {
        self.fileURL = fileURL
        if let fileURL, let data = try? Data(contentsOf: fileURL), let saved = try? JSONDecoder().decode(State.self, from: data) {
            state = saved
        } else {
            state = State()
        }
    }

    /// `Library/Application Support/sync-metadata.json` under `directory`.
    public static func file(in directory: URL) -> SyncMetadataStore {
        let folder = directory.appendingPathComponent("Library/Application Support", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return SyncMetadataStore(fileURL: folder.appendingPathComponent("sync-metadata.json"))
    }

    public var snapshot: State { state }

    public func cursor(for table: SyncTable) -> SyncCursor? { state.cursors[table.rawValue] }

    public func setCursor(_ cursor: SyncCursor, for table: SyncTable) {
        state.cursors[table.rawValue] = cursor
        save()
    }

    public func recordFailure(id: UUID, reason: String) {
        state.failures[id] = reason
        save()
    }

    public func clearFailures(_ ids: some Sequence<UUID>) {
        var changed = false
        for id in ids where state.failures.removeValue(forKey: id) != nil { changed = true }
        if changed { save() }
    }

    public func failureReason(id: UUID) -> String? { state.failures[id] }

    public func didSync(at date: Date, clockOffset: TimeInterval) {
        state.lastSyncedAt = date
        state.clockOffset = clockOffset
        save()
    }

    public func setRestoreCompleted(_ value: Bool) {
        state.restoreCompleted = value
        save()
    }

    /// Starts over for `userId`: no cursors, no failures, restore not done.
    public func reset(owner userId: UUID?) {
        state = State(ownerUserId: userId)
        save()
    }

    private func save() {
        guard let fileURL, let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}

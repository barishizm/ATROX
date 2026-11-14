import Foundation

/// The coach's server data (RLS-scoped tables and the delete functions).
public protocol CoachRemote: Sendable {
    func threads(limit: Int, before: Date?) async throws -> [CoachThread]
    /// Newest first, at most `limit`, older than `before` when given.
    func messages(threadId: UUID, limit: Int, before: Date?) async throws -> [CoachStoredMessage]
    func renameThread(id: UUID, title: String) async throws
    func deleteThread(id: UUID) async throws
    func deleteAllThreads() async throws
    func memory() async throws -> [CoachMemoryNote]
    func editMemory(id: UUID, note: String) async throws
    func deleteMemory(id: UUID) async throws
    func recordDecision(proposalID: String, decision: CoachProposal.Decision) async throws
}

/// What the device remembers between launches, so the list and the open conversation show up instantly.
public struct CoachCacheSnapshot: Sendable, Codable, Equatable {
    public var threads: [CoachThread] = []
    public var messages: [String: [CoachMessage]] = [:]

    public init(threads: [CoachThread] = [], messages: [String: [CoachMessage]] = [:]) {
        self.threads = threads
        self.messages = messages
    }
}

public protocol CoachCache: Sendable {
    func load() -> CoachCacheSnapshot
    func save(_ snapshot: CoachCacheSnapshot)
}

/// JSON file in Application Support. Cached conversations are server-owned and re-fetched, so a file is enough and
/// needs no SwiftData migration.
public struct FileCoachCache: CoachCache {
    private let url: URL

    public init(url: URL) {
        self.url = url
    }

    public func load() -> CoachCacheSnapshot {
        guard let data = try? Data(contentsOf: url) else { return CoachCacheSnapshot() }
        return (try? JSONDecoder().decode(CoachCacheSnapshot.self, from: data)) ?? CoachCacheSnapshot()
    }

    public func save(_ snapshot: CoachCacheSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: [.atomic, .completeFileProtection])
    }

    /// Removes the file (sign-out, delete all).
    public func clear() {
        try? FileManager.default.removeItem(at: url)
    }
}

public struct InMemoryCoachCache: CoachCache {
    private let box = Box()

    public init() {}

    public func load() -> CoachCacheSnapshot { box.value }
    public func save(_ snapshot: CoachCacheSnapshot) { box.value = snapshot }

    private final class Box: @unchecked Sendable {
        private let lock = NSLock()
        private var stored = CoachCacheSnapshot()
        var value: CoachCacheSnapshot {
            get { lock.withLock { stored } }
            set { lock.withLock { stored = newValue } }
        }
    }
}

/// Conversations and messages: cache first, then the server in pages. Writes go to the server first and then update the
/// cache, so a failed delete never makes a conversation disappear from the screen.
public actor CoachRepository {
    public static let threadPage = 30
    public static let messagePage = 40
    /// Conversations whose messages stay in the cache (the newest ones).
    static let cachedThreadLimit = 10

    private let remote: any CoachRemote
    private let cache: any CoachCache
    private var snapshot: CoachCacheSnapshot

    public init(remote: any CoachRemote, cache: any CoachCache) {
        self.remote = remote
        self.cache = cache
        snapshot = cache.load()
    }

    public func cachedThreads() -> [CoachThread] { snapshot.threads }

    public func cachedMessages(threadId: UUID) -> [CoachMessage] { snapshot.messages[Self.key(threadId)] ?? [] }

    /// First page from the server; replaces the list.
    @discardableResult
    public func refreshThreads() async throws -> [CoachThread] {
        let page = try await remote.threads(limit: Self.threadPage, before: nil)
        snapshot.threads = page
        trimMessages()
        persist()
        return page
    }

    /// The next page after the oldest conversation we have.
    @discardableResult
    public func olderThreads() async throws -> [CoachThread] {
        guard let oldest = snapshot.threads.last?.updatedAt else { return [] }
        let page = try await remote.threads(limit: Self.threadPage, before: oldest)
        let known = Set(snapshot.threads.map(\.id))
        snapshot.threads += page.filter { !known.contains($0.id) }
        persist()
        return page
    }

    /// The newest page of a conversation from the server (replaces the cached copy).
    public func refreshMessages(threadId: UUID) async throws -> [CoachMessage] {
        let rows = try await remote.messages(threadId: threadId, limit: Self.messagePage, before: nil)
        let messages = CoachHistory.messages(from: rows)
        snapshot.messages[Self.key(threadId)] = messages
        persist()
        return messages
    }

    /// Messages older than the oldest one we have (scrolling up), merged into the cache.
    public func olderMessages(threadId: UUID) async throws -> [CoachMessage] {
        let current = cachedMessages(threadId: threadId)
        guard let oldest = current.first?.createdAt else { return current }
        let rows = try await remote.messages(threadId: threadId, limit: Self.messagePage, before: oldest)
        let known = Set(current.map(\.id))
        let merged = CoachHistory.messages(from: rows).filter { !known.contains($0.id) } + current
        snapshot.messages[Self.key(threadId)] = merged
        persist()
        return merged
    }

    /// Keeps the cache in step with a conversation the user just had (the stream is the source of truth until the
    /// next refresh).
    public func remember(threadId: UUID, messages: [CoachMessage], title: String?) {
        snapshot.messages[Self.key(threadId)] = messages.filter { $0.status != .streaming }
        if let index = snapshot.threads.firstIndex(where: { $0.id == threadId }) {
            snapshot.threads[index].updatedAt = Date()
            let thread = snapshot.threads.remove(at: index)
            snapshot.threads.insert(thread, at: 0)
        } else {
            snapshot.threads.insert(CoachThread(id: threadId, title: title, createdAt: Date(), updatedAt: Date()), at: 0)
        }
        trimMessages()
        persist()
    }

    public func rename(threadId: UUID, title: String) async throws {
        let clean = String(title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200))
        guard !clean.isEmpty else { return }
        try await remote.renameThread(id: threadId, title: clean)
        if let index = snapshot.threads.firstIndex(where: { $0.id == threadId }) { snapshot.threads[index].title = clean }
        persist()
    }

    public func delete(threadId: UUID) async throws {
        try await remote.deleteThread(id: threadId)
        snapshot.threads.removeAll { $0.id == threadId }
        snapshot.messages[Self.key(threadId)] = nil
        persist()
    }

    public func deleteAll() async throws {
        try await remote.deleteAllThreads()
        snapshot = CoachCacheSnapshot()
        persist()
    }

    public func recordDecision(proposalID: String, decision: CoachProposal.Decision) async {
        for (key, messages) in snapshot.messages {
            var changed = messages
            for index in changed.indices {
                if let position = changed[index].proposals.firstIndex(where: { $0.id == proposalID }) {
                    changed[index].proposals[position].decision = decision
                }
            }
            snapshot.messages[key] = changed
        }
        persist()
        do {
            try await remote.recordDecision(proposalID: proposalID, decision: decision)
        } catch {
            // The card already shows the decision; the coach just does not hear about it this time.
        }
    }

    public func memory() async throws -> [CoachMemoryNote] { try await remote.memory() }

    public func editMemory(id: UUID, note: String) async throws {
        try await remote.editMemory(id: id, note: note.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    public func deleteMemory(id: UUID) async throws { try await remote.deleteMemory(id: id) }

    /// Sign-out: nothing of the user stays on the device.
    public func clear() {
        snapshot = CoachCacheSnapshot()
        persist()
    }

    private func trimMessages() {
        let keep = Set(snapshot.threads.prefix(Self.cachedThreadLimit).map { Self.key($0.id) })
        snapshot.messages = snapshot.messages.filter { keep.contains($0.key) }
    }

    private func persist() { cache.save(snapshot) }

    private static func key(_ id: UUID) -> String { id.uuidString.lowercased() }
}

import Foundation
import Security

/// Where the random `contribution_key` lives. One key per signed-in user on this device, never sent with the account.
public protocol ContributionKeyStore: Sendable {
    /// The current key and when it was made, or nil.
    func current(userId: UUID) -> (key: UUID, createdAt: Date)?
    func create(userId: UUID, now: Date) -> UUID
    func destroy(userId: UUID)
}

/// Remembers what was sent last (for "once a month" and the transparency screen). Local only.
public protocol ContributionStateStore: Sendable {
    func lastSent(userId: UUID) -> ContributionPayload?
    func save(_ payload: ContributionPayload, userId: UUID)
    func clear(userId: UUID)
}

public protocol ContributionTransport: Sendable {
    func send(_ payload: ContributionPayload) async throws
    /// Removes every row stored under the key.
    func delete(contributionKey: UUID) async throws
}

/// The data the summary needs for one user and one month window.
public protocol ContributionDataSource: Sendable {
    func summary(userId: UUID, key: UUID, month: (label: String, firstDay: Int, lastDay: Int)) async -> ContributionPayload?
}

public enum ContributionOutcome: Sendable, Equatable {
    case sent(month: String)
    case notDue
    case noConsent
    case nothingToSend
}

/// Monthly anonymous contribution (P093). Sends only while consent is current, at most once per finished month,
/// and rotates the key every 12 months. Withdrawing consent deletes the server rows and destroys the key.
public struct ContributionService: Sendable {
    public static let keyLifetimeDays = 365

    private let consents: ConsentService
    private let keys: any ContributionKeyStore
    private let state: any ContributionStateStore
    private let transport: any ContributionTransport
    private let data: any ContributionDataSource
    private let clock: @Sendable () -> Date
    private let calendar: Calendar

    public init(
        consents: ConsentService, keys: any ContributionKeyStore, state: any ContributionStateStore, transport: any ContributionTransport,
        data: any ContributionDataSource, clock: @escaping @Sendable () -> Date = { Date() }, calendar: Calendar = .current
    ) {
        self.consents = consents
        self.keys = keys
        self.state = state
        self.transport = transport
        self.data = data
        self.clock = clock
        self.calendar = calendar
    }

    /// Call after launch / sync. Cheap when nothing is due.
    @discardableResult
    public func sendIfDue(userId: UUID) async throws -> ContributionOutcome {
        guard try await consents.isContributing(userId: userId) else {
            // A withdrawal whose deletion request failed is retried here; the key is still on the device.
            if keys.current(userId: userId) != nil { try? await withdraw(userId: userId) }
            return .noConsent
        }
        let now = clock()
        guard let month = ContributionSummary.previousMonth(now: now, calendar: calendar) else { return .nothingToSend }
        if let last = state.lastSent(userId: userId), last.month >= month.label { return .notDue }
        let key = try await activeKey(userId: userId, now: now)
        guard let payload = await data.summary(userId: userId, key: key, month: month) else { return .nothingToSend }
        try await transport.send(payload)
        state.save(payload, userId: userId)
        return .sent(month: month.label)
    }

    /// Consent withdrawn: delete what the server holds under the key, then forget the key. If the request fails the key
    /// is kept so the deletion can be retried; the caller sees the error.
    public func withdraw(userId: UUID) async throws {
        if let existing = keys.current(userId: userId) {
            try await transport.delete(contributionKey: existing.key)
        }
        keys.destroy(userId: userId)
        state.clear(userId: userId)
    }

    /// "What was shared last month?": what was sent, or what would be sent next, as the readable payload.
    public func lastMonthPreview(userId: UUID) async -> (payload: ContributionPayload, wasSent: Bool)? {
        if let sent = state.lastSent(userId: userId) { return (sent, true) }
        guard let month = ContributionSummary.previousMonth(now: clock(), calendar: calendar) else { return nil }
        // Preview only: a placeholder key, nothing is stored or sent.
        guard let payload = await data.summary(userId: userId, key: keys.current(userId: userId)?.key ?? UUID(), month: month) else { return nil }
        return (payload, false)
    }

    private func activeKey(userId: UUID, now: Date) async throws -> UUID {
        if let existing = keys.current(userId: userId) {
            let age = calendar.dateComponents([.day], from: existing.createdAt, to: now).day ?? 0
            if age < Self.keyLifetimeDays { return existing.key }
            // Rotation: the old key's rows are no longer needed under that identity; they stay as an anonymous history.
            keys.destroy(userId: userId)
        }
        return keys.create(userId: userId, now: now)
    }
}

// MARK: - Stores

public final class InMemoryContributionKeyStore: ContributionKeyStore, @unchecked Sendable {
    private let lock = NSLock()
    private var items: [UUID: (key: UUID, createdAt: Date)] = [:]

    public init() {}

    public func current(userId: UUID) -> (key: UUID, createdAt: Date)? { lock.withLock { items[userId] } }

    public func create(userId: UUID, now: Date) -> UUID {
        let key = UUID()
        lock.withLock { items[userId] = (key, now) }
        return key
    }

    public func destroy(userId: UUID) { lock.withLock { items[userId] = nil } }
}

/// The key in the Keychain (this device only, available after first unlock, not in backups).
public struct KeychainContributionKeyStore: ContributionKeyStore {
    private let service: String

    public init(service: String = "app.atrox.contribution-key") { self.service = service }

    private func query(_ userId: UUID) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: userId.uuidString.lowercased()]
    }

    public func current(userId: UUID) -> (key: UUID, createdAt: Date)? {
        var request = query(userId)
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(request as CFDictionary, &out) == errSecSuccess, let data = out as? Data,
              let record = try? JSONDecoder().decode(Record.self, from: data) else { return nil }
        return (record.key, record.createdAt)
    }

    public func create(userId: UUID, now: Date) -> UUID {
        let key = UUID()
        destroy(userId: userId)
        var item = query(userId)
        item[kSecValueData as String] = try? JSONEncoder().encode(Record(key: key, createdAt: now))
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(item as CFDictionary, nil)
        return key
    }

    public func destroy(userId: UUID) { SecItemDelete(query(userId) as CFDictionary) }

    private struct Record: Codable {
        var key: UUID
        var createdAt: Date
    }
}

public final class UserDefaultsContributionStateStore: ContributionStateStore, @unchecked Sendable {
    // UserDefaults is thread-safe.
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    private func name(_ userId: UUID) -> String { "contribution.last.\(userId.uuidString.lowercased())" }

    public func lastSent(userId: UUID) -> ContributionPayload? {
        defaults.data(forKey: name(userId)).flatMap { try? JSONDecoder().decode(ContributionPayload.self, from: $0) }
    }

    public func save(_ payload: ContributionPayload, userId: UUID) {
        if let data = try? JSONEncoder().encode(payload) { defaults.set(data, forKey: name(userId)) }
    }

    public func clear(userId: UUID) { defaults.removeObject(forKey: name(userId)) }
}

/// The summary read from the local store through `ScoreService`.
public struct ScoreServiceContributionSource: ContributionDataSource {
    private let scores: ScoreService

    public init(scores: ScoreService) { self.scores = scores }

    public func summary(userId: UUID, key: UUID, month: (label: String, firstDay: Int, lastDay: Int)) async -> ContributionPayload? {
        await scores.contributionSummary(userId: userId, key: key, month: month)
    }
}

import Foundation
import Observation

/// Where the last known entitlement is kept between launches, per user. Offline the cached value stays valid until its
/// own expiry date passes.
protocol EntitlementCache: Sendable {
    func load(userId: UUID) -> ProEntitlement?
    func save(_ entitlement: ProEntitlement, userId: UUID)
    func clear(userId: UUID)
}

struct UserDefaultsEntitlementCache: EntitlementCache, @unchecked Sendable {
    // UserDefaults is thread-safe; the class is not annotated Sendable.
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    private func key(_ userId: UUID) -> String { "entitlement.\(userId.uuidString.lowercased())" }

    func load(userId: UUID) -> ProEntitlement? {
        defaults.data(forKey: key(userId)).flatMap { try? JSONDecoder().decode(ProEntitlement.self, from: $0) }
    }

    func save(_ entitlement: ProEntitlement, userId: UUID) {
        if let data = try? JSONEncoder().encode(entitlement) { defaults.set(data, forKey: key(userId)) }
    }

    func clear(userId: UUID) { defaults.removeObject(forKey: key(userId)) }
}

/// The app's single source of truth for "is the user Pro" (P089). Screens and feature gates read only this.
/// It merges the device's StoreKit state with the server's `entitlements` row (`ProEntitlement.merge`) and keeps the
/// last known result for offline use. `PurchaseService` feeds it; nothing else writes it.
@MainActor
@Observable
final class Entitlements {
    private(set) var current: ProEntitlement
    private(set) var userId: UUID?

    @ObservationIgnored private var local: ProEntitlement?
    @ObservationIgnored private var server: ProEntitlement?
    @ObservationIgnored private let cache: any EntitlementCache
    @ObservationIgnored private let clock: @Sendable () -> Date

    init(cache: any EntitlementCache = UserDefaultsEntitlementCache(), clock: @escaping @Sendable () -> Date = { Date() }) {
        self.cache = cache
        self.clock = clock
        self.current = .free
    }

    var now: Date { clock() }
    var isPro: Bool { current.isPro(at: now) }
    var isTrial: Bool { current.isTrial(at: now) }
    var expiresAt: Date? { current.expiresAt }
    var willRenew: Bool { current.willRenew }

    /// A user signed in: the last known entitlement applies immediately, before StoreKit or the server answer.
    func begin(userId: UUID) {
        guard self.userId != userId else { return }
        self.userId = userId
        local = nil
        server = nil
        current = cache.load(userId: userId) ?? .free
    }

    /// Sign-out: nothing of the previous user may leak to the next one.
    func end() {
        if let userId { cache.clear(userId: userId) }
        userId = nil
        local = nil
        server = nil
        current = .free
    }

    func update(local: ProEntitlement) {
        self.local = local
        recompute()
    }

    /// `nil` clears the server view (no row); a failed fetch should not call this, so the last answer stays.
    func update(server: ProEntitlement?) {
        self.server = server
        recompute()
    }

    private func recompute() {
        // Before StoreKit has answered, the cached value stands in for the local side.
        let merged = ProEntitlement.merge(local: local ?? current, server: server, now: now)
        current = merged
        if let userId { cache.save(merged, userId: userId) }
    }
}

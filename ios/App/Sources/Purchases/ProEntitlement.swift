import Foundation

/// Product identifiers of the single subscription group (P089). They must match App Store Connect and `StoreKit/ATROX.storekit`.
enum ProProduct {
    static let monthly = "atrox.pro.monthly"
    static let yearly = "atrox.pro.yearly"
    static let all = [yearly, monthly]
}

/// What the user is entitled to. Derived from verified StoreKit data and, when reachable, from the server's
/// `entitlements` table; the app asks `Entitlements`, never StoreKit, whether the user is Pro.
struct ProEntitlement: Equatable, Codable, Sendable {
    enum Status: String, Codable, Sendable {
        /// Never subscribed.
        case none
        case active
        /// Free introductory trial.
        case trial
        /// Renewal payment failed but Apple keeps access on for a while.
        case gracePeriod
        /// Payment failed and the grace period (if any) is over; no access while Apple retries.
        case billingRetry
        case expired
        /// Refunded or revoked by Apple (or family sharing ended).
        case revoked
    }

    var status: Status
    var productID: String?
    /// End of paid access: the period end, or the grace-period end while in grace.
    var expiresAt: Date?
    var willRenew: Bool

    static let free = ProEntitlement(status: .none, productID: nil, expiresAt: nil, willRenew: false)

    /// Pro right now? Access states also need an unexpired date, so a cached entitlement lapses by itself offline.
    func isPro(at now: Date) -> Bool {
        switch status {
        case .active, .trial, .gracePeriod:
            guard let expiresAt else { return false }
            return expiresAt > now
        case .none, .billingRetry, .expired, .revoked:
            return false
        }
    }

    func isTrial(at now: Date) -> Bool { status == .trial && isPro(at: now) }

    /// The paid access ended and the user may buy again (drives "your subscription ended" copy).
    var hasLapsed: Bool { status == .expired || status == .billingRetry || status == .revoked }
}

/// One subscription as StoreKit reports it, already verified. The pure rules below turn these into a `ProEntitlement`.
struct SubscriptionRecord: Equatable, Sendable {
    enum State: Sendable { case subscribed, inGracePeriod, inBillingRetry, expired, revoked }

    var productID: String
    var state: State
    var expirationDate: Date?
    var gracePeriodExpirationDate: Date?
    var isTrial: Bool
    var willRenew: Bool
    /// Token set at purchase time (`AppAccountToken`); nil for purchases made before it was used.
    var appAccountToken: UUID?
}

extension ProEntitlement {
    /// The entitlement the given StoreKit records add up to for the user who owns `accountToken`.
    /// Records bought for another ATROX account on the same Apple ID are ignored; the server maps them to that account too.
    static func derive(from records: [SubscriptionRecord], accountToken: UUID?, now: Date) -> ProEntitlement {
        let mine = records.filter { $0.appAccountToken == nil || accountToken == nil || $0.appAccountToken == accountToken }
        let candidates = mine.map(entitlement(for:))
        if let best = candidates.filter({ $0.isPro(at: now) }).max(by: { ($0.expiresAt ?? .distantPast) < ($1.expiresAt ?? .distantPast) }) {
            return best
        }
        // Not Pro: report the most informative lapse (revoked > billing retry > expired), latest first.
        let rank: (ProEntitlement) -> Int = { ent in
            switch ent.status {
            case .revoked: 3
            case .billingRetry: 2
            case .expired: 1
            default: 0
            }
        }
        return candidates.max { (rank($0), $0.expiresAt ?? .distantPast) < (rank($1), $1.expiresAt ?? .distantPast) } ?? .free
    }

    private static func entitlement(for record: SubscriptionRecord) -> ProEntitlement {
        switch record.state {
        case .subscribed:
            ProEntitlement(
                status: record.isTrial ? .trial : .active, productID: record.productID,
                expiresAt: record.expirationDate, willRenew: record.willRenew
            )
        case .inGracePeriod:
            ProEntitlement(
                status: .gracePeriod, productID: record.productID,
                expiresAt: record.gracePeriodExpirationDate ?? record.expirationDate, willRenew: record.willRenew
            )
        case .inBillingRetry:
            ProEntitlement(status: .billingRetry, productID: record.productID, expiresAt: record.expirationDate, willRenew: true)
        case .expired:
            ProEntitlement(status: .expired, productID: record.productID, expiresAt: record.expirationDate, willRenew: false)
        case .revoked:
            ProEntitlement(status: .revoked, productID: record.productID, expiresAt: record.expirationDate, willRenew: false)
        }
    }

    /// Combines what this device's StoreKit says with the server row.
    /// - A refund/revocation seen locally wins: the server learns about it only through Apple's notification.
    /// - Otherwise either side granting access is enough (a purchase the server saw but this device has not synced yet,
    ///   or one the device has verified but the server has not been told about yet); the later expiry is kept.
    static func merge(local: ProEntitlement, server: ProEntitlement?, now: Date) -> ProEntitlement {
        if local.status == .revoked { return local }
        guard let server else { return local }
        switch (local.isPro(at: now), server.isPro(at: now)) {
        case (true, true):
            return (server.expiresAt ?? .distantPast) > (local.expiresAt ?? .distantPast) ? server : local
        case (true, false): return local
        case (false, true): return server
        case (false, false):
            return local.status == .none ? server : local
        }
    }
}

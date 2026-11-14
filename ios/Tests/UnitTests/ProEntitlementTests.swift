import Foundation
import Testing

@testable import ATROX

struct ProEntitlementTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let day: TimeInterval = 86400

    func record(
        _ state: SubscriptionRecord.State, expires: TimeInterval, trial: Bool = false, grace: TimeInterval? = nil,
        token: UUID? = nil, product: String = ProProduct.yearly
    ) -> SubscriptionRecord {
        SubscriptionRecord(
            productID: product, state: state, expirationDate: now.addingTimeInterval(expires),
            gracePeriodExpirationDate: grace.map { now.addingTimeInterval($0) }, isTrial: trial, willRenew: true, appAccountToken: token
        )
    }

    @Test func noRecordsMeansFree() {
        let result = ProEntitlement.derive(from: [], accountToken: nil, now: now)
        #expect(result == .free)
        #expect(!result.isPro(at: now))
    }

    @Test func subscribedIsProUntilExpiry() {
        let result = ProEntitlement.derive(from: [record(.subscribed, expires: 10 * day)], accountToken: nil, now: now)
        #expect(result.status == .active)
        #expect(result.isPro(at: now))
        #expect(!result.isPro(at: now.addingTimeInterval(11 * day)))
    }

    @Test func trialIsProAndFlagged() {
        let result = ProEntitlement.derive(from: [record(.subscribed, expires: 7 * day, trial: true)], accountToken: nil, now: now)
        #expect(result.status == .trial)
        #expect(result.isTrial(at: now))
        #expect(result.isPro(at: now))
    }

    @Test func gracePeriodKeepsAccessUntilItsOwnEnd() {
        let result = ProEntitlement.derive(from: [record(.inGracePeriod, expires: -1 * day, grace: 5 * day)], accountToken: nil, now: now)
        #expect(result.status == .gracePeriod)
        #expect(result.isPro(at: now))
        #expect(!result.isPro(at: now.addingTimeInterval(6 * day)))
    }

    @Test func billingRetryHasNoAccess() {
        let result = ProEntitlement.derive(from: [record(.inBillingRetry, expires: -1 * day)], accountToken: nil, now: now)
        #expect(result.status == .billingRetry)
        #expect(!result.isPro(at: now))
        #expect(result.hasLapsed)
    }

    @Test func expiredAndRevokedAreNotPro() {
        let expired = ProEntitlement.derive(from: [record(.expired, expires: -3 * day)], accountToken: nil, now: now)
        #expect(expired.status == .expired && !expired.isPro(at: now))
        let revoked = ProEntitlement.derive(from: [record(.revoked, expires: 30 * day)], accountToken: nil, now: now)
        #expect(revoked.status == .revoked && !revoked.isPro(at: now))
    }

    @Test func activeBeatsAnOlderLapsedRecord() {
        let result = ProEntitlement.derive(
            from: [record(.expired, expires: -40 * day, product: ProProduct.monthly), record(.subscribed, expires: 300 * day)],
            accountToken: nil, now: now
        )
        #expect(result.status == .active)
        #expect(result.productID == ProProduct.yearly)
    }

    @Test func recordsOfAnotherAccountAreIgnored() {
        let mine = AppAccountToken.make(for: UUID())
        let other = AppAccountToken.make(for: UUID())
        #expect(ProEntitlement.derive(from: [record(.subscribed, expires: day, token: other)], accountToken: mine, now: now) == .free)
        #expect(ProEntitlement.derive(from: [record(.subscribed, expires: day, token: mine)], accountToken: mine, now: now).isPro(at: now))
        // A purchase from before tokens were used still counts.
        #expect(ProEntitlement.derive(from: [record(.subscribed, expires: day, token: nil)], accountToken: mine, now: now).isPro(at: now))
    }

    // MARK: Merge with the server

    func entitlement(_ status: ProEntitlement.Status, expires: TimeInterval?) -> ProEntitlement {
        ProEntitlement(status: status, productID: ProProduct.monthly, expiresAt: expires.map { now.addingTimeInterval($0) }, willRenew: true)
    }

    @Test func serverGrantsWhenTheDeviceHasNotSyncedYet() {
        let merged = ProEntitlement.merge(local: .free, server: entitlement(.active, expires: 10 * day), now: now)
        #expect(merged.isPro(at: now))
    }

    @Test func deviceGrantsWhenTheServerHasNotBeenTold() {
        let local = entitlement(.active, expires: 10 * day)
        #expect(ProEntitlement.merge(local: local, server: entitlement(.expired, expires: -day), now: now) == local)
        #expect(ProEntitlement.merge(local: local, server: nil, now: now) == local)
    }

    @Test func laterExpiryWinsWhenBothGrant() {
        let local = entitlement(.active, expires: 5 * day)
        let server = entitlement(.active, expires: 9 * day)
        #expect(ProEntitlement.merge(local: local, server: server, now: now) == server)
    }

    @Test func localRevocationBeatsAStaleServerRow() {
        let local = entitlement(.revoked, expires: 30 * day)
        let merged = ProEntitlement.merge(local: local, server: entitlement(.active, expires: 30 * day), now: now)
        #expect(!merged.isPro(at: now))
        #expect(merged.status == .revoked)
    }

    @Test func lapsedBothSidesKeepsTheLocalReason() {
        let local = entitlement(.expired, expires: -day)
        #expect(ProEntitlement.merge(local: local, server: entitlement(.expired, expires: -2 * day), now: now) == local)
        #expect(ProEntitlement.merge(local: .free, server: entitlement(.expired, expires: -day), now: now).status == .expired)
    }
}

struct AppAccountTokenTests {
    @Test func isStablePerUserAndDistinctAcrossUsers() {
        let user = UUID()
        #expect(AppAccountToken.make(for: user) == AppAccountToken.make(for: user))
        #expect(AppAccountToken.make(for: user) != AppAccountToken.make(for: UUID()))
        #expect(AppAccountToken.make(for: user) != user)
    }

    @Test func isAVersion5UUID() {
        let token = AppAccountToken.make(for: UUID()).uuid
        #expect(token.6 >> 4 == 5)
        #expect(token.8 >> 6 == 0b10)
    }

    @Test func matchesAKnownVector() {
        // Same as Python `uuid.uuid5(namespace, user_id)`; the server (appstore-notifications, P090) must reproduce it.
        let user = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        #expect(AppAccountToken.make(for: user).uuidString.lowercased() == "b74ace79-3051-5fbe-8b18-7a4c598b8ebf")
    }
}

struct SupabaseEntitlementSourceTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func picksTheRowThatGrantsAccess() {
        let rows = [
            SupabaseEntitlementSource.Row(productId: ProProduct.monthly, status: "expired", expiresAt: now.addingTimeInterval(-86400)),
            SupabaseEntitlementSource.Row(productId: ProProduct.yearly, status: "active", expiresAt: now.addingTimeInterval(86400))
        ]
        #expect(SupabaseEntitlementSource.best(of: rows, now: now)?.productID == ProProduct.yearly)
        #expect(SupabaseEntitlementSource.best(of: [], now: now) == nil)
    }

    @Test func mapsStatusStrings() {
        #expect(SupabaseEntitlementSource.status(for: "active") == .active)
        #expect(SupabaseEntitlementSource.status(for: "grace_period") == .gracePeriod)
        #expect(SupabaseEntitlementSource.status(for: "refunded") == .revoked)
        #expect(SupabaseEntitlementSource.status(for: "whatever") == .expired)
    }
}

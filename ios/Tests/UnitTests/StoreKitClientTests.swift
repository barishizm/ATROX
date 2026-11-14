import Foundation
import StoreKit
import StoreKitTest
import Testing

@testable import ATROX

/// Runs the real `StoreKitClient` against StoreKitTest's simulated App Store (`StoreKit/ATROX.storekit`): purchase,
/// renewal, expiry, refund and restore. Serialized because there is one StoreKit test session per process.
@MainActor
@Suite(.serialized)
struct StoreKitClientTests {
    final class BundleToken {}

    func makeSession() throws -> SKTestSession {
        let url = try #require(Bundle(for: BundleToken.self).url(forResource: "ATROX", withExtension: "storekit"))
        let session = try SKTestSession(contentsOf: url)
        session.resetToDefaultState()
        session.disableDialogs = true
        session.clearTransactions()
        return session
    }

    func makeService(userId: UUID) async -> PurchaseService {
        let service = PurchaseService(store: StoreKitClient(), entitlements: Entitlements(cache: NoCache()))
        await service.start(userId: userId)
        return service
    }

    struct NoCache: EntitlementCache {
        func load(userId: UUID) -> ProEntitlement? { nil }
        func save(_ entitlement: ProEntitlement, userId: UUID) {}
        func clear(userId: UUID) {}
    }

    @Test func loadsLocalizedPlansWithTheYearlyTrial() async throws {
        _ = try makeSession()
        let service = await makeService(userId: UUID())
        #expect(service.products.map(\.id) == [ProProduct.yearly, ProProduct.monthly])
        #expect(service.products[0].trialDays == 7)
        #expect(service.products[0].isTrialEligible)
        #expect(service.products[1].trialDays == nil)
    }

    @Test func buyingYearlyStartsATrial() async throws {
        _ = try makeSession()
        let service = await makeService(userId: UUID())
        #expect(!service.isPro)
        #expect(try await service.purchase(service.products[0]) == .success)
        #expect(service.isPro)
        #expect(service.entitlements.isTrial)
    }

    @Test func buyingMonthlyIsPaidAccess() async throws {
        _ = try makeSession()
        let service = await makeService(userId: UUID())
        let monthly = try #require(service.products.first { $0.id == ProProduct.monthly })
        try await service.purchase(monthly)
        #expect(service.isPro)
        #expect(!service.entitlements.isTrial)
        #expect(service.entitlements.current.productID == ProProduct.monthly)
    }

    @Test func expiryRemovesAccess() async throws {
        let session = try makeSession()
        let service = await makeService(userId: UUID())
        let monthly = try #require(service.products.first { $0.id == ProProduct.monthly })
        try await service.purchase(monthly)
        try session.expireSubscription(productIdentifier: ProProduct.monthly)
        // StoreKit reports the expiry a moment later.
        for _ in 0..<50 {
            await service.refresh()
            if !service.isPro { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        #expect(!service.isPro)
        #expect(service.entitlements.current.status == .expired)
    }

    @Test func refundRevokesAccess() async throws {
        let session = try makeSession()
        let service = await makeService(userId: UUID())
        let monthly = try #require(service.products.first { $0.id == ProProduct.monthly })
        try await service.purchase(monthly)
        let transaction = try #require(session.allTransactions().first)
        try session.refundTransaction(identifier: UInt(transaction.originalTransactionIdentifier))
        await service.refresh()
        #expect(!service.isPro)
        #expect(service.entitlements.current.status == .revoked)
    }

    @Test func renewalKeepsAccess() async throws {
        let session = try makeSession()
        session.timeRate = .monthlyRenewalEveryThirtySeconds
        let service = await makeService(userId: UUID())
        let monthly = try #require(service.products.first { $0.id == ProProduct.monthly })
        try await service.purchase(monthly)
        try await Task.sleep(for: .seconds(1))
        try session.forceRenewalOfSubscription(productIdentifier: ProProduct.monthly)
        await service.refresh()
        #expect(service.isPro)
    }

    @Test func purchaseOfAnotherAccountDoesNotUnlockThisOne() async throws {
        _ = try makeSession()
        let buyer = await makeService(userId: UUID())
        let monthly = try #require(buyer.products.first { $0.id == ProProduct.monthly })
        try await buyer.purchase(monthly)
        // Same Apple ID, different ATROX account.
        let other = await makeService(userId: UUID())
        #expect(!other.isPro)
    }

    @Test func restoreFindsAnExistingPurchase() async throws {
        let session = try makeSession()
        try await session.buyProduct(identifier: ProProduct.monthly)
        let service = await makeService(userId: UUID())
        // Bought outside the app without a token: still counts.
        #expect(service.isPro)
        #expect(try await service.restore())
    }
}

import Foundation
import Testing

@testable import ATROX

/// Server stand-in whose answer the test controls.
fileprivate final class StubServer: EntitlementServerSource, @unchecked Sendable {
    var result: Result<ProEntitlement?, Error> = .success(nil)
    var verified: [String] = []
    var verifyError: Error?
    func fetch() async throws -> ProEntitlement? { try result.get() }
    func verify(signedTransaction: String) async throws {
        verified.append(signedTransaction)
        if let verifyError { throw verifyError }
    }
}

fileprivate final class MemoryCache: EntitlementCache, @unchecked Sendable {
    var values: [UUID: ProEntitlement] = [:]
    func load(userId: UUID) -> ProEntitlement? { values[userId] }
    func save(_ entitlement: ProEntitlement, userId: UUID) { values[userId] = entitlement }
    func clear(userId: UUID) { values[userId] = nil }
}

@MainActor
struct PurchaseServiceTests {
    let user = UUID()

    fileprivate func make(
        store: FakeStoreClient = FakeStoreClient(), server: StubServer = StubServer(), cache: MemoryCache = MemoryCache()
    ) -> (PurchaseService, FakeStoreClient, StubServer, MemoryCache) {
        (PurchaseService(store: store, server: server, entitlements: Entitlements(cache: cache)), store, server, cache)
    }

    @Test func startLoadsProductsYearlyFirst() async {
        let (service, _, _, _) = make()
        await service.start(userId: user)
        #expect(service.products.map(\.id) == [ProProduct.yearly, ProProduct.monthly])
        #expect(!service.isPro)
    }

    @Test func purchaseCarriesTheDerivedAccountTokenAndTurnsPro() async throws {
        let (service, store, _, _) = make()
        await service.start(userId: user)
        let result = try await service.purchase(service.products[0])
        #expect(result == .success)
        #expect(service.isPro)
        #expect(store.purchasedTokens == [AppAccountToken.make(for: user)])
    }

    @Test func successfulPurchaseIsSentToTheServer() async throws {
        let (service, _, server, _) = make()
        await service.start(userId: user)
        try await service.purchase(service.products[0])
        #expect(server.verified == ["fake-jws.\(ProProduct.yearly)"])
    }

    @Test func serverVerificationFailureDoesNotBlockThePurchase() async throws {
        let (service, _, server, _) = make()
        server.verifyError = URLError(.notConnectedToInternet)
        await service.start(userId: user)
        #expect(try await service.purchase(service.products[0]) == .success)
        #expect(service.isPro)
    }

    @Test func pendingAndCancelledPurchasesDoNotGrantAccess() async throws {
        let (service, store, _, _) = make()
        await service.start(userId: user)
        store.setPurchaseResult(.pending)
        #expect(try await service.purchase(service.products[0]) == .pending)
        #expect(service.hasPendingPurchase && !service.isPro)
        store.setPurchaseResult(.cancelled)
        #expect(try await service.purchase(service.products[0]) == .cancelled)
        #expect(!service.isPro)
    }

    @Test func purchaseNeedsASignedInUser() async {
        let (service, _, _, _) = make()
        await #expect(throws: PurchaseService.Failure.notSignedIn) { try await service.purchase(FakeStoreClient.defaultCatalog[0]) }
    }

    @Test func transactionUpdatesRefreshTheEntitlement() async throws {
        let (service, store, _, _) = make()
        await service.start(userId: user)
        #expect(!service.isPro)
        store.setRecords([
            SubscriptionRecord(
                productID: ProProduct.monthly, state: .subscribed, expirationDate: Date().addingTimeInterval(86400),
                gracePeriodExpirationDate: nil, isTrial: false, willRenew: true, appAccountToken: AppAccountToken.make(for: user)
            )
        ])
        store.emitUpdate()
        for _ in 0..<50 where !service.isPro { try await Task.sleep(for: .milliseconds(20)) }
        #expect(service.isPro)
    }

    @Test func restoreSyncsAndReportsTheResult() async throws {
        let (service, store, _, _) = make()
        await service.start(userId: user)
        store.setRecords([
            SubscriptionRecord(
                productID: ProProduct.yearly, state: .subscribed, expirationDate: Date().addingTimeInterval(86400),
                gracePeriodExpirationDate: nil, isTrial: false, willRenew: true, appAccountToken: nil
            )
        ])
        #expect(try await service.restore())
        #expect(service.entitlements.isPro)
    }

    @Test func restoreSurfacesStoreErrors() async {
        let (service, store, _, _) = make()
        await service.start(userId: user)
        store.setSyncError(URLError(.notConnectedToInternet))
        await #expect(throws: URLError.self) { try await service.restore() }
    }

    @Test func serverEntitlementGrantsProWithoutLocalPurchase() async {
        let server = StubServer()
        server.result = .success(ProEntitlement(status: .active, productID: ProProduct.yearly, expiresAt: Date().addingTimeInterval(86400), willRenew: true))
        let (service, _, _, _) = make(server: server)
        await service.start(userId: user)
        #expect(service.isPro)
    }

    @Test func aFailingServerKeepsTheLastKnownAnswer() async {
        let server = StubServer()
        server.result = .success(ProEntitlement(status: .active, productID: ProProduct.yearly, expiresAt: Date().addingTimeInterval(86400), willRenew: true))
        let (service, _, _, _) = make(server: server)
        await service.start(userId: user)
        server.result = .failure(URLError(.notConnectedToInternet))
        await service.refresh()
        #expect(service.isPro)
    }

    @Test func lastKnownStateSurvivesARelaunchOffline() async {
        let cache = MemoryCache()
        cache.values[user] = ProEntitlement(status: .active, productID: ProProduct.monthly, expiresAt: Date().addingTimeInterval(86400), willRenew: true)
        let entitlements = Entitlements(cache: cache)
        entitlements.begin(userId: user)
        #expect(entitlements.isPro)
    }

    @Test func aCachedEntitlementLapsesAtItsExpiry() {
        let cache = MemoryCache()
        cache.values[user] = ProEntitlement(status: .active, productID: ProProduct.monthly, expiresAt: Date().addingTimeInterval(-60), willRenew: true)
        let entitlements = Entitlements(cache: cache)
        entitlements.begin(userId: user)
        #expect(!entitlements.isPro)
    }

    @Test func stopClearsTheUsersEntitlement() async throws {
        let (service, _, _, cache) = make()
        await service.start(userId: user)
        try await service.purchase(service.products[0])
        #expect(service.isPro && cache.values[user] != nil)
        service.stop()
        #expect(!service.isPro && cache.values[user] == nil)
    }
}

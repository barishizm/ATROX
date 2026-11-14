import Foundation
import Observation

/// StoreKit 2 purchase flow (P089): loads the plans, buys, restores, listens for transaction changes and feeds
/// `Entitlements`. Screens read `entitlements` for "is Pro" and this service for the plans and actions.
@MainActor
@Observable
final class PurchaseService {
    enum Failure: Error, Equatable {
        case notSignedIn
        case storeUnavailable
    }

    private(set) var products: [PurchaseProduct] = []
    private(set) var isLoadingProducts = false
    private(set) var isPurchasing = false
    /// The last purchase is waiting for approval (Ask to Buy); cleared when the entitlement changes.
    private(set) var hasPendingPurchase = false
    let entitlements: Entitlements

    @ObservationIgnored private let store: any StoreClient
    @ObservationIgnored private let server: any EntitlementServerSource
    @ObservationIgnored private var accountToken: UUID?
    @ObservationIgnored private var updatesTask: Task<Void, Never>?

    init(store: any StoreClient, server: any EntitlementServerSource = NoEntitlementServer(), entitlements: Entitlements = Entitlements()) {
        self.store = store
        self.server = server
        self.entitlements = entitlements
    }

    var isPro: Bool { entitlements.isPro }

    /// Signed in: starts listening for transactions and reads the current state. Safe to call again for the same user.
    func start(userId: UUID) async {
        let token = AppAccountToken.make(for: userId)
        if accountToken != token {
            stopListening()
            accountToken = token
            entitlements.begin(userId: userId)
        }
        if updatesTask == nil {
            updatesTask = Task { [weak self, store] in
                for await _ in store.updates() {
                    guard !Task.isCancelled else { return }
                    await self?.refresh()
                }
            }
        }
        await refresh()
        await loadProducts()
    }

    /// Sign-out.
    func stop() {
        stopListening()
        accountToken = nil
        hasPendingPurchase = false
        entitlements.end()
    }

    private func stopListening() {
        updatesTask?.cancel()
        updatesTask = nil
    }

    func loadProducts() async {
        guard !isLoadingProducts else { return }
        isLoadingProducts = true
        defer { isLoadingProducts = false }
        if let loaded = try? await store.products() { products = loaded }
    }

    /// Re-reads StoreKit and the server. A failed server call keeps the previous server answer.
    func refresh() async {
        guard accountToken != nil else { return }
        let records = await store.records()
        let local = ProEntitlement.derive(from: records, accountToken: accountToken, now: entitlements.now)
        entitlements.update(local: local)
        if local.isPro(at: entitlements.now) { hasPendingPurchase = false }
        if let row = try? await server.fetch() { entitlements.update(server: row) }
    }

    @discardableResult
    func purchase(_ product: PurchaseProduct) async throws -> PurchaseResult {
        guard let accountToken else { throw Failure.notSignedIn }
        isPurchasing = true
        defer { isPurchasing = false }
        let result = try await store.purchase(productID: product.id, accountToken: accountToken)
        switch result {
        case .success:
            hasPendingPurchase = false
            await refresh()
        case .pending: hasPendingPurchase = true
        case .cancelled: break
        }
        return result
    }

    /// "Restore purchases": asks the App Store to sync, then re-reads. Returns whether the user is Pro afterwards.
    @discardableResult
    func restore() async throws -> Bool {
        guard accountToken != nil else { throw Failure.notSignedIn }
        try await store.sync()
        await refresh()
        return isPro
    }

    func showManageSubscriptions() async throws { try await store.showManageSubscriptions() }
}

/// In-memory store for tests and `-uitest-fake-purchases`: the "purchase" flips a switch.
final class FakeStoreClient: StoreClient, @unchecked Sendable {
    private let lock = NSLock()
    private var _records: [SubscriptionRecord] = []
    private var _result: PurchaseResult = .success
    private var _syncError: Error?
    private var continuations: [AsyncStream<Void>.Continuation] = []
    private(set) var purchasedTokens: [UUID?] = []
    var catalog: [PurchaseProduct]

    init(catalog: [PurchaseProduct] = FakeStoreClient.defaultCatalog) { self.catalog = catalog }

    static let defaultCatalog = [
        PurchaseProduct(id: ProProduct.yearly, displayName: "Pro Yearly", displayPrice: "$59.99", price: 59.99, period: .year, trialDays: 7, isTrialEligible: true),
        PurchaseProduct(id: ProProduct.monthly, displayName: "Pro Monthly", displayPrice: "$9.99", price: 9.99, period: .month, trialDays: nil, isTrialEligible: false)
    ]

    func setRecords(_ records: [SubscriptionRecord]) { lock.withLock { _records = records } }
    func setPurchaseResult(_ result: PurchaseResult) { lock.withLock { _result = result } }
    func setSyncError(_ error: Error?) { lock.withLock { _syncError = error } }
    /// Simulates `Transaction.updates` firing.
    func emitUpdate() { lock.withLock { continuations.forEach { $0.yield() } } }

    func products() async throws -> [PurchaseProduct] { catalog }

    func purchase(productID: String, accountToken: UUID?) async throws -> PurchaseResult {
        let result: PurchaseResult = lock.withLock {
            purchasedTokens.append(accountToken)
            return _result
        }
        if result == .success {
            let expires = Date().addingTimeInterval(productID == ProProduct.yearly ? 365 * 86400 : 30 * 86400)
            lock.withLock {
                _records = [SubscriptionRecord(
                    productID: productID, state: .subscribed, expirationDate: expires, gracePeriodExpirationDate: nil,
                    isTrial: false, willRenew: true, appAccountToken: accountToken
                )]
            }
        }
        return result
    }

    func records() async -> [SubscriptionRecord] { lock.withLock { _records } }

    func updates() -> AsyncStream<Void> {
        AsyncStream { continuation in lock.withLock { continuations.append(continuation) } }
    }

    func sync() async throws { if let error = lock.withLock({ _syncError }) { throw error } }
    func showManageSubscriptions() async throws {}
}

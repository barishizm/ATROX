import Foundation
import StoreKit
import UIKit

/// A subscription plan as the paywall needs it. Prices come localized from StoreKit.
struct PurchaseProduct: Identifiable, Equatable, Sendable {
    enum Period: Sendable { case month, year }

    var id: String
    var displayName: String
    var displayPrice: String
    var price: Decimal
    var period: Period
    /// Length of the free trial in days, if the plan has one.
    var trialDays: Int?
    /// Whether this Apple ID can still get the trial (it is once per subscription group).
    var isTrialEligible: Bool
    /// ISO code of the storefront currency, to format derived amounts (the monthly equivalent of the yearly plan).
    var currencyCode: String = "USD"
}

enum PurchaseResult: Equatable, Sendable {
    /// Verified and finished; the entitlement is re-read afterwards.
    case success
    /// Waiting for approval (Ask to Buy, SCA); a later `updates()` event completes it.
    case pending
    case cancelled
}

/// The StoreKit calls `PurchaseService` needs. A protocol so the service is testable without Apple's frameworks.
protocol StoreClient: Sendable {
    func products() async throws -> [PurchaseProduct]
    func purchase(productID: String, accountToken: UUID?) async throws -> PurchaseResult
    /// Verified subscription state of the current Apple ID.
    func records() async -> [SubscriptionRecord]
    /// Fires after a transaction changes outside a purchase (renewal, refund, Ask to Buy, purchase on another device).
    func updates() -> AsyncStream<Void>
    /// Asks the App Store to re-sync purchases (prompts for the Apple ID password).
    func sync() async throws
    @MainActor func showManageSubscriptions() async throws
    /// App Store signed JWS (`jwsRepresentation`) of the current Pro transactions, for server verification (P090).
    func signedTransactions() async -> [String]
}

extension StoreClient {
    func signedTransactions() async -> [String] { [] }
}

enum StoreClientError: Error, Equatable {
    case unknownProduct
    case unverified
}

/// The real StoreKit 2 implementation.
struct StoreKitClient: StoreClient {
    func products() async throws -> [PurchaseProduct] {
        let products = try await Product.products(for: ProProduct.all)
        var result: [PurchaseProduct] = []
        for product in products {
            guard let info = product.subscription else { continue }
            let eligible = await info.isEligibleForIntroOffer
            let trial = info.introductoryOffer.flatMap { $0.paymentMode == .freeTrial ? Self.days(in: $0.period) : nil }
            result.append(PurchaseProduct(
                id: product.id, displayName: product.displayName, displayPrice: product.displayPrice, price: product.price,
                period: info.subscriptionPeriod.unit == .year ? .year : .month,
                trialDays: trial, isTrialEligible: eligible && trial != nil, currencyCode: product.priceFormatStyle.currencyCode
            ))
        }
        // Yearly first: it is the plan the paywall highlights.
        return result.sorted { $0.period == .year && $1.period != .year }
    }

    func purchase(productID: String, accountToken: UUID?) async throws -> PurchaseResult {
        guard let product = try await Product.products(for: [productID]).first else { throw StoreClientError.unknownProduct }
        var options: Set<Product.PurchaseOption> = []
        if let accountToken { options.insert(.appAccountToken(accountToken)) }
        switch try await product.purchase(options: options) {
        case .success(let verification):
            guard case .verified(let transaction) = verification else { throw StoreClientError.unverified }
            await transaction.finish()
            return .success
        case .pending: return .pending
        case .userCancelled: return .cancelled
        @unknown default: return .cancelled
        }
    }

    func records() async -> [SubscriptionRecord] {
        if let statuses = try? await Product.products(for: ProProduct.all).first?.subscription?.status, !statuses.isEmpty {
            return statuses.compactMap(Self.record(from:))
        }
        // Products could not be loaded (offline, App Store down): the device still knows the verified entitlements.
        var records: [SubscriptionRecord] = []
        for await result in Transaction.currentEntitlements {
            guard case .verified(let tx) = result, ProProduct.all.contains(tx.productID) else { continue }
            records.append(Self.record(from: tx, state: tx.revocationDate == nil ? .subscribed : .revoked, willRenew: false, grace: nil))
        }
        return records
    }

    func updates() -> AsyncStream<Void> {
        AsyncStream { continuation in
            let task = Task {
                for await result in Transaction.updates {
                    if case .verified(let transaction) = result { await transaction.finish() }
                    continuation.yield()
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func sync() async throws { try await AppStore.sync() }

    func signedTransactions() async -> [String] {
        var result: [String] = []
        for await entitlement in Transaction.currentEntitlements {
            guard case .verified(let transaction) = entitlement, ProProduct.all.contains(transaction.productID) else { continue }
            result.append(entitlement.jwsRepresentation)
        }
        return result
    }

    @MainActor
    func showManageSubscriptions() async throws {
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else { return }
        try await AppStore.showManageSubscriptions(in: scene)
    }

    // MARK: Mapping

    private static func record(from status: Product.SubscriptionInfo.Status) -> SubscriptionRecord? {
        guard case .verified(let transaction) = status.transaction, ProProduct.all.contains(transaction.productID) else { return nil }
        var willRenew = false
        var grace: Date?
        if case .verified(let renewal) = status.renewalInfo {
            willRenew = renewal.willAutoRenew
            grace = renewal.gracePeriodExpirationDate
        }
        let state: SubscriptionRecord.State
        switch status.state {
        case .subscribed: state = .subscribed
        case .inGracePeriod: state = .inGracePeriod
        case .inBillingRetryPeriod: state = .inBillingRetry
        case .revoked: state = .revoked
        default: state = .expired
        }
        return record(from: transaction, state: state, willRenew: willRenew, grace: grace)
    }

    private static func record(
        from transaction: Transaction, state: SubscriptionRecord.State, willRenew: Bool, grace: Date?
    ) -> SubscriptionRecord {
        SubscriptionRecord(
            productID: transaction.productID, state: state, expirationDate: transaction.expirationDate,
            gracePeriodExpirationDate: grace,
            isTrial: transaction.offer?.type == .introductory && transaction.offer?.paymentMode == .freeTrial,
            willRenew: willRenew, appAccountToken: transaction.appAccountToken
        )
    }

    private static func days(in period: Product.SubscriptionPeriod) -> Int {
        switch period.unit {
        case .day: period.value
        case .week: period.value * 7
        case .month: period.value * 30
        case .year: period.value * 365
        @unknown default: period.value
        }
    }
}

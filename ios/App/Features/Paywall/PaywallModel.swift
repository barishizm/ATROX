import Foundation
import Observation

/// State of the paywall (P091): which plan is chosen, what the buy button says, and the outcome of buying or restoring.
@MainActor
@Observable
final class PaywallModel {
    enum Message: Equatable {
        case purchaseFailed
        case pending
        case restoreNothingFound
        case restoreFailed
    }

    private(set) var message: Message?
    private(set) var isRestoring = false
    var selectedID: String?

    private let purchases: PurchaseService

    init(purchases: PurchaseService) { self.purchases = purchases }

    var products: [PurchaseProduct] { purchases.products }
    var isPro: Bool { purchases.isPro }
    var isBusy: Bool { purchases.isPurchasing || isRestoring }
    var isLoadingProducts: Bool { purchases.isLoadingProducts }
    var entitlements: Entitlements { purchases.entitlements }

    /// The chosen plan; the yearly plan until the user picks another.
    var selected: PurchaseProduct? {
        products.first { $0.id == selectedID } ?? products.first { $0.period == .year } ?? products.first
    }

    var yearly: PurchaseProduct? { products.first { $0.period == .year } }
    var monthly: PurchaseProduct? { products.first { $0.period == .month } }

    /// The yearly price per month, e.g. "$5.00": what the paywall shows next to the yearly plan.
    var yearlyMonthlyEquivalent: Decimal? { yearly.map { Self.monthlyEquivalent(of: $0) } }

    /// Whole-percent saving of yearly over twelve monthly payments; nil when it is not a saving.
    var yearlySavingsPercent: Int? {
        guard let yearly, let monthly else { return nil }
        return Self.savingsPercent(yearly: yearly.price, monthly: monthly.price)
    }

    /// Trial days shown on the button: only when the selected plan has a trial this Apple ID can still use.
    var trialDays: Int? {
        guard let selected, selected.isTrialEligible else { return nil }
        return selected.trialDays
    }

    static func monthlyEquivalent(of product: PurchaseProduct) -> Decimal {
        product.period == .year ? product.price / 12 : product.price
    }

    static func savingsPercent(yearly: Decimal, monthly: Decimal) -> Int? {
        guard monthly > 0, yearly > 0 else { return nil }
        let full = monthly * 12
        guard yearly < full else { return nil }
        let percent = (full - yearly) / full * 100
        return NSDecimalNumber(decimal: percent).rounding(accordingToBehavior: nil).intValue
    }

    func load() async {
        if products.isEmpty { await purchases.loadProducts() }
    }

    func purchase() async {
        guard let product = selected else { return }
        message = nil
        do {
            switch try await purchases.purchase(product) {
            case .success, .cancelled: break
            case .pending: message = .pending
            }
        } catch {
            message = .purchaseFailed
        }
    }

    func restore() async {
        message = nil
        isRestoring = true
        defer { isRestoring = false }
        do {
            if try await purchases.restore() == false { message = .restoreNothingFound }
        } catch {
            message = .restoreFailed
        }
    }

    func manageSubscription() async { try? await purchases.showManageSubscriptions() }
}

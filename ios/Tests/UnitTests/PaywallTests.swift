import Foundation
import StrengthKit
import Testing

@testable import ATROX

fileprivate final class NoCache: EntitlementCache, @unchecked Sendable {
    func load(userId: UUID) -> ProEntitlement? { nil }
    func save(_ entitlement: ProEntitlement, userId: UUID) {}
    func clear(userId: UUID) {}
}

struct FeatureGateTests {
    @Test func freeUsersAreLockedOutOfEveryProFeature() {
        for feature in ProFeature.allCases {
            #expect(FeatureGate.isLocked(feature, isPro: false), "\(feature)")
            #expect(!FeatureGate.isLocked(feature, isPro: true), "\(feature)")
        }
    }

    @Test func gymGroupStaysFreeOthersArePro() {
        #expect(!FeatureGate.isLocked(population: .gym, isPro: false))
        #expect(FeatureGate.isLocked(population: .general, isPro: false))
        #expect(FeatureGate.isLocked(population: .competitor, isPro: false))
        for group in ReferencePopulation.allCases { #expect(!FeatureGate.isLocked(population: group, isPro: true)) }
    }

    @Test func insightHistoryCutoffAppliesToFreeOnly() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(FeatureGate.insightHistoryCutoff(now: now, isPro: true) == nil)
        let cutoff = FeatureGate.insightHistoryCutoff(now: now, isPro: false)
        #expect(cutoff.map { now.timeIntervalSince($0) } == Double(FeatureGate.freeInsightHistoryDays) * 86_400)
    }
}

@MainActor
struct PaywallModelTests {
    let user = UUID()

    // swiftlint:disable:next large_tuple
    private func make(store: FakeStoreClient = FakeStoreClient()) -> (PaywallModel, PurchaseService, FakeStoreClient) {
        let service = PurchaseService(store: store, entitlements: Entitlements(cache: NoCache()))
        return (PaywallModel(purchases: service), service, store)
    }

    @Test func yearlyIsPreselectedWithMonthlyEquivalentAndSaving() async {
        let (model, _, _) = make()
        await model.load()
        #expect(model.selected?.id == ProProduct.yearly)
        #expect(model.yearlyMonthlyEquivalent.map { NSDecimalNumber(decimal: $0).doubleValue } == 59.99 / 12)
        // 12 × 9.99 = 119.88 → 59.99 saves about half.
        #expect(model.yearlySavingsPercent == 50)
    }

    @Test func savingsArePureAndNilWhenNotASaving() {
        #expect(PaywallModel.savingsPercent(yearly: 60, monthly: 10) == 50)
        #expect(PaywallModel.savingsPercent(yearly: 120, monthly: 10) == nil)
        #expect(PaywallModel.savingsPercent(yearly: 130, monthly: 10) == nil)
        #expect(PaywallModel.savingsPercent(yearly: 0, monthly: 10) == nil)
    }

    @Test func trialShowsOnlyForAnEligiblePlan() async {
        let (model, _, _) = make()
        await model.load()
        #expect(model.trialDays == 7)
        model.selectedID = ProProduct.monthly
        #expect(model.trialDays == nil)
    }

    @Test func purchaseUnlocksProAtOnce() async {
        let (model, service, _) = make()
        await service.start(userId: user)
        await model.load()
        #expect(!model.isPro)
        await model.purchase()
        #expect(model.isPro)
        #expect(model.message == nil)
    }

    @Test func pendingPurchaseExplainsAndStaysFree() async {
        let (model, service, store) = make()
        await service.start(userId: user)
        store.setPurchaseResult(.pending)
        await model.purchase()
        #expect(model.message == .pending)
        #expect(!model.isPro)
    }

    @Test func cancelledPurchaseIsSilent() async {
        let (model, service, store) = make()
        await service.start(userId: user)
        store.setPurchaseResult(.cancelled)
        await model.purchase()
        #expect(model.message == nil)
    }

    @Test func failedPurchaseShowsAnError() async {
        let (model, _, _) = make()  // not signed in: purchase throws
        await model.load()
        await model.purchase()
        #expect(model.message == .purchaseFailed)
    }

    @Test func restoreWithoutSubscriptionSaysSo() async {
        let (model, service, _) = make()
        await service.start(userId: user)
        await model.restore()
        #expect(model.message == .restoreNothingFound)
        #expect(!model.isRestoring)
    }

    @Test func restoreBringsProBack() async {
        let (model, service, store) = make()
        await service.start(userId: user)
        let token = AppAccountToken.make(for: user)
        store.setRecords([SubscriptionRecord(
            productID: ProProduct.yearly, state: .subscribed, expirationDate: Date().addingTimeInterval(86_400 * 300),
            gracePeriodExpirationDate: nil, isTrial: false, willRenew: true, appAccountToken: token
        )])
        await model.restore()
        #expect(model.isPro)
        #expect(model.message == nil)
    }
}

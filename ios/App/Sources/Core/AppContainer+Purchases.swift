import DataKit
import Foundation

/// Subscription wiring of the composition root (P089).
extension AppContainer {
    /// Production: StoreKit 2 plus the user's `entitlements` row when Supabase is configured.
    static func makePurchases(
        config: SupabaseConfiguration?, accessToken: @escaping @Sendable () async -> String?
    ) -> PurchaseService {
        let server: any EntitlementServerSource = config.map {
            SupabaseEntitlementSource(configuration: $0, accessToken: accessToken)
        } ?? NoEntitlementServer()
        return PurchaseService(store: StoreKitClient(), server: server)
    }

    /// Follows the session: a signed-in user starts the purchase service, signing out stops it. Idempotent.
    func syncPurchases() async {
        if let user = await currentUser() {
            await purchases.start(userId: user.id)
        } else {
            purchases.stop()
        }
    }
}

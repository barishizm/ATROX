import DesignSystem
import SwiftData
import SwiftUI
import UserNotifications

@main
struct ATROXApp: App {
    @State private var container: AppContainer
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // The background tasks must find the container even when the system launches the app only for them,
        // before any view (and its `.task`) exists.
        let live = AppContainer.live()
        _container = State(initialValue: live)
        BackgroundSync.shared.coordinator = live.sync
        WeeklySummaryBackground.shared.container = live
        DiagnosticsCollector.shared.start()
        AppAnalytics.shared.appLaunched()
        BackgroundSync.shared.register()
        WeeklySummaryBackground.shared.register()
        UNUserNotificationCenter.current().delegate = NotificationRouter.shared
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(container)
                .modifier(LocalStoreModifier(container: container.modelContainer))
                .task { await container.prepareCatalog() }
                .task {
                    NotificationRouter.shared.onWeeklySummary = { container.deepLinks.receive(.weeklySummary) }
                    await container.rescheduleWeeklySummary()
                }
                .task { await container.checkModelUpdate() }
                .task(id: container.root.state) {
                    await container.syncPurchases()
                    await container.sendContributionIfDue()
                }
        }
        .onChange(of: scenePhase) { _, phase in
            // Sync triggers (P045): coming to the foreground syncs and starts the 15-minute timer; leaving stops it.
            switch phase {
            case .active:
                container.sync?.appBecameActive()
                Task { await container.checkModelUpdate() }
                Task { await container.rescheduleWeeklySummary() }
                Task { await container.purchases.refresh() }
                container.openPendingIntentLink()
                Task { await container.refreshWidgets() }
            case .background:
                container.sync?.appEnteredBackground()
                BackgroundSync.shared.schedule()
            default: break
            }
        }
    }
}

/// Injects the SwiftData container into the view tree when one exists.
private struct LocalStoreModifier: ViewModifier {
    let container: ModelContainer?

    func body(content: Content) -> some View {
        if let container { content.modelContainer(container) } else { content }
    }
}

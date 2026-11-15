import DataKit
import Foundation
import WidgetKit

/// Widgets, controls and Shortcuts (P096): the app side. The widgets read a snapshot from the app group; this file
/// keeps it current and answers the intents that need the running app.
extension AppContainer {
    /// Connects the App Intents to this container; called once at launch.
    func installIntentHandlers() {
        IntentCommandCenter.shared.openLink = { [weak self] url in self?.deepLinks.receive(url: url) }
        IntentCommandCenter.shared.logWeight = { [weak self] kilograms in
            await self?.logWeight(kilograms: kilograms) ?? .failed
        }
    }

    /// "Log my weight": saves a manual weigh-in for the signed-in user.
    func logWeight(kilograms: Double, now: Date = Date()) async -> WeightLogOutcome {
        guard let modelContainer else { return .failed }
        guard let user = await currentUser() else { return .signedOut }
        do {
            _ = try await SwiftDataMeasurementRepository(modelContainer: modelContainer)
                .add(MeasurementInput(date: now, weightKg: kilograms), userId: user.id)
            return .saved
        } catch {
            Log.app.error("Weigh-in from an intent failed: \(error)")
            return .failed
        }
    }

    /// Opens the link an intent left in the app group while the app was not running.
    func openPendingIntentLink() {
        guard let url = PendingLinkInbox.appGroup()?.take() else { return }
        deepLinks.receive(url: url)
    }

    /// Recomputes what the widgets show and reloads their timelines when it changed. Called after the scores
    /// refresh (every local save, so a finished workout included) and when the app comes to the front.
    func refreshWidgets() async {
        guard let store = WidgetSnapshotStore.appGroup() else { return }
        if isRefreshingWidgets {
            widgetsDirty = true
            return
        }
        isRefreshingWidgets = true
        defer { isRefreshingWidgets = false }
        repeat {
            widgetsDirty = false
            guard await currentUser() != nil, let model = await makeTodayModel(forWidgets: true) else { return }
            await model.load()
            guard let snapshot = model.widgetSnapshot() else { return }
            if store.write(snapshot) { WidgetCenter.shared.reloadAllTimelines() }
        } while widgetsDirty
    }

    /// Sign-out: widgets fall back to their "sign in" state.
    func clearWidgets() {
        WidgetSnapshotStore.appGroup()?.clear()
        WidgetCenter.shared.reloadAllTimelines()
    }
}

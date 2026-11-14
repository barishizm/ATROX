import Foundation
import UserNotifications

/// Receives notification taps. Only the weekly summary (P070) opens something; the handler is attached once the
/// container exists, so a tap that cold-starts the app is remembered until then.
@MainActor
final class NotificationRouter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationRouter()

    private var pendingWeekly = false
    var onWeeklySummary: (@MainActor () -> Void)? {
        didSet {
            guard pendingWeekly, let onWeeklySummary else { return }
            pendingWeekly = false
            onWeeklySummary()
        }
    }

    func openWeeklySummary() {
        if let onWeeklySummary { onWeeklySummary() } else { pendingWeekly = true }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse
    ) async {
        guard response.notification.request.identifier == WeeklySummaryNotification.identifier else { return }
        await MainActor.run { NotificationRouter.shared.openWeeklySummary() }
    }
}

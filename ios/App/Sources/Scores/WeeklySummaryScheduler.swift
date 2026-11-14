import BackgroundTasks
import DataKit
import Foundation

enum WeeklySummaryNotification {
    static let identifier = "weekly-summary"
}

/// The user's choices for the weekly summary notification (Settings).
enum WeeklySummarySettings {
    static let enabledKey = "weeklySummary.enabled"
    static let hourKey = "weeklySummary.hour"
    static let minuteKey = "weeklySummary.minute"

    static var isEnabled: Bool { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }
    static var hour: Int { UserDefaults.standard.object(forKey: hourKey) as? Int ?? WeeklySchedule.defaultHour }
    static var minute: Int { UserDefaults.standard.object(forKey: minuteKey) as? Int ?? 0 }
}

/// Weekly summary wiring of the composition root (P070).
extension AppContainer {
    /// Schedules (or cancels) the Sunday-evening notification. The text carries the numbers known right now, so it is
    /// refreshed after every score refresh, on foreground and by the background task.
    func rescheduleWeeklySummary() async {
        let notifications = UserNotificationService()
        let id = WeeklySummaryNotification.identifier
        guard WeeklySummarySettings.isEnabled, await notifications.authorizationStatus() == .authorized,
              let fire = WeeklySchedule.nextFire(after: Date(), hour: WeeklySummarySettings.hour, minute: WeeklySummarySettings.minute)
        else {
            await notifications.cancel(id: id)
            return
        }
        let locale = language.effectiveLocale()
        var summary: WeeklySummary?
        if let modelContainer, let service = scoreService, let user = await currentUser() {
            summary = await TrainingStats(modelContainer: modelContainer).weeklySummary(
                userId: user.id, weekContaining: fire, population: await service.preferredPopulation(userId: user.id)
            )
        }
        let text = WeeklySummaryPresenter.notification(for: summary, locale: locale)
        try? await notifications.schedule(LocalNotification(id: id, title: text.title, body: text.body, fireDate: fire))
        WeeklySummaryBackground.shared.schedule(before: fire)
    }

    func makeWeeklySummaryModel() async -> WeeklySummaryModel? {
        guard let modelContainer, let service = scoreService, let insights = insightService(),
              let context = await makeHistoryContext() else { return nil }
        _ = await scoreCenter()
        return WeeklySummaryModel(
            context: context, stats: TrainingStats(modelContainer: modelContainer), scores: service, insights: insights,
            comments: await makeCommentProvider()
        )
    }
}

/// Prepares the next notification in the background (`BGAppRefreshTask`); when the system does not run it, the app does
/// the same work on the next launch.
@MainActor
final class WeeklySummaryBackground {
    static let identifier = "com.barishizm.atrox.weekly.refresh"
    static let shared = WeeklySummaryBackground()

    weak var container: AppContainer?

    func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.identifier, using: .main) { task in
            MainActor.assumeIsolated {
                guard let refresh = task as? BGAppRefreshTask else { return task.setTaskCompleted(success: false) }
                WeeklySummaryBackground.shared.handle(refresh)
            }
        }
    }

    /// Asks to run a couple of hours before the notification fires.
    func schedule(before fire: Date) {
        let request = BGAppRefreshTaskRequest(identifier: Self.identifier)
        request.earliestBeginDate = max(Date(timeIntervalSinceNow: 15 * 60), fire.addingTimeInterval(-2 * 3600))
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            Log.app.info("Weekly summary refresh not scheduled: \(error.localizedDescription)", privacy: .public)
        }
    }

    private func handle(_ task: BGAppRefreshTask) {
        guard let container else { return task.setTaskCompleted(success: false) }
        let work = Task { await container.rescheduleWeeklySummary() }
        task.expirationHandler = { work.cancel() }
        Task {
            await work.value
            task.setTaskCompleted(success: !work.isCancelled)
        }
    }
}

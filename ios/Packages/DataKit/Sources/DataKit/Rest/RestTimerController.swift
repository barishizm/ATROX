import Foundation
import Observation

/// The rest timer between sets (P037). The end moment is an absolute `Date` taken from the clock, so the countdown
/// survives backgrounding; while the app is in the background a local notification is scheduled for that moment.
@MainActor
@Observable
public final class RestTimerController {
    public static let notificationId = "atrox.rest-timer"
    public static let primerSeenKey = "workout.rest.primerSeen"
    public static let adjustStep: TimeInterval = 15

    public struct Run: Equatable, Sendable {
        public let startedAt: Date
        public var endsAt: Date
        /// Length of the ring: grows and shrinks with ±15 s.
        public var total: TimeInterval
    }

    /// The running countdown; nil when idle.
    public private(set) var run: Run?
    /// Increments each time a countdown runs out in the foreground (drives haptics).
    public private(set) var finishCount = 0
    /// True when the explanation screen before the system notification prompt should be shown.
    public var showsPermissionPrimer = false

    @ObservationIgnored private let clock: @Sendable () -> Date
    @ObservationIgnored private let notifications: any NotificationService
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let sleep: @Sendable (TimeInterval) async throws -> Void
    @ObservationIgnored private var title = ""
    @ObservationIgnored private var body = ""
    @ObservationIgnored private var isForeground = true
    @ObservationIgnored private var waiter: Task<Void, Never>?
    /// Called when a countdown finishes in the foreground (sound).
    @ObservationIgnored public var onFinished: (@MainActor () -> Void)?

    public init(
        clock: @escaping @Sendable () -> Date = { Date() }, notifications: any NotificationService,
        defaults: UserDefaults = .standard,
        sleep: @escaping @Sendable (TimeInterval) async throws -> Void = { try await Task.sleep(for: .seconds($0)) }
    ) {
        self.clock = clock
        self.notifications = notifications
        self.defaults = defaults
        self.sleep = sleep
    }

    public var isRunning: Bool { run != nil }

    public func remaining(at date: Date? = nil) -> TimeInterval {
        guard let run else { return 0 }
        return max(0, run.endsAt.timeIntervalSince(date ?? clock()))
    }

    /// 1 at the start, 0 at the end.
    public func fraction(at date: Date? = nil) -> Double {
        guard let run, run.total > 0 else { return 0 }
        return min(1, remaining(at: date) / run.total)
    }

    // MARK: Control

    /// Starts (or restarts) a countdown. `title` / `body` are the notification text.
    public func start(seconds: Int, title: String, body: String) async {
        guard seconds > 0 else { return }
        self.title = title
        self.body = body
        let now = clock()
        run = Run(startedAt: now, endsAt: now.addingTimeInterval(TimeInterval(seconds)), total: TimeInterval(seconds))
        armWaiter()
        if await notifications.authorizationStatus() == .notDetermined, !defaults.bool(forKey: Self.primerSeenKey) {
            showsPermissionPrimer = true
        }
    }

    /// +15 / −15 seconds. Taking off more than what is left ends the countdown without the finish cue.
    public func adjust(by seconds: TimeInterval) async {
        guard var current = run else { return }
        current.endsAt = current.endsAt.addingTimeInterval(seconds)
        current.total = max(1, current.total + seconds)
        if current.endsAt <= clock() {
            await skip()
            return
        }
        run = current
        armWaiter()
        if !isForeground { await scheduleNotification() }
    }

    /// Ends the countdown now, without a cue.
    public func skip() async {
        waiter?.cancel()
        waiter = nil
        run = nil
        await notifications.cancel(id: Self.notificationId)
    }

    // MARK: Scene phase

    /// Call when the app goes to the background (`active: false`) or comes back (`active: true`).
    public func scenePhaseChanged(active: Bool) async {
        isForeground = active
        if active {
            await notifications.cancel(id: Self.notificationId)
            if let run, run.endsAt <= clock() {
                // Ran out while away: the notification already told the user.
                self.run = nil
                waiter?.cancel()
                waiter = nil
            } else {
                armWaiter()
            }
        } else {
            waiter?.cancel()
            waiter = nil
            await scheduleNotification()
        }
    }

    // MARK: Permission primer

    /// "Allow" on the explanation screen: now ask the system.
    public func acceptPrimer() async {
        defaults.set(true, forKey: Self.primerSeenKey)
        showsPermissionPrimer = false
        _ = await notifications.requestAuthorization()
        if !isForeground { await scheduleNotification() }
    }

    public func declinePrimer() {
        defaults.set(true, forKey: Self.primerSeenKey)
        showsPermissionPrimer = false
    }

    // MARK: Internals

    /// Ends a countdown that reached zero while the app is open. Public so tests (and the view) can drive it.
    public func finishIfDue() async {
        guard let run, run.endsAt <= clock(), isForeground else { return }
        self.run = nil
        waiter = nil
        finishCount += 1
        onFinished?()
        await notifications.cancel(id: Self.notificationId)
    }

    private func armWaiter() {
        waiter?.cancel()
        guard let run, isForeground else { return }
        let delay = max(0, run.endsAt.timeIntervalSince(clock()))
        let sleep = self.sleep
        waiter = Task { [weak self] in
            do { try await sleep(delay) } catch { return }
            await self?.finishIfDue()
        }
    }

    private func scheduleNotification() async {
        guard let run, run.endsAt > clock(), await notifications.authorizationStatus() == .authorized else { return }
        try? await notifications.schedule(
            LocalNotification(id: Self.notificationId, title: title, body: body, fireDate: run.endsAt)
        )
    }
}

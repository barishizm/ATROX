import Foundation

public enum NotificationAuthorization: Sendable, Equatable {
    case notDetermined
    case denied
    case authorized
}

/// A local notification that fires at a fixed moment.
public struct LocalNotification: Sendable, Equatable {
    public let id: String
    public let title: String
    public let body: String
    public let fireDate: Date

    public init(id: String, title: String, body: String, fireDate: Date) {
        self.id = id
        self.title = title
        self.body = body
        self.fireDate = fireDate
    }
}

/// Local notifications behind a protocol so the rest timer can be tested without `UNUserNotificationCenter`.
public protocol NotificationService: Sendable {
    func authorizationStatus() async -> NotificationAuthorization
    /// Shows the system permission prompt. Returns whether notifications are now allowed.
    func requestAuthorization() async -> Bool
    /// Schedules (or replaces the pending notification with the same id).
    func schedule(_ notification: LocalNotification) async throws
    func cancel(id: String) async
}

/// In-memory `NotificationService` for tests and previews.
public actor FakeNotificationService: NotificationService {
    public private(set) var scheduled: [String: LocalNotification] = [:]
    public private(set) var requestCount = 0
    private var status: NotificationAuthorization
    private let grantsOnRequest: Bool

    public init(status: NotificationAuthorization = .notDetermined, grantsOnRequest: Bool = true) {
        self.status = status
        self.grantsOnRequest = grantsOnRequest
    }

    public func authorizationStatus() -> NotificationAuthorization { status }

    public func requestAuthorization() -> Bool {
        requestCount += 1
        if status == .notDetermined { status = grantsOnRequest ? .authorized : .denied }
        return status == .authorized
    }

    public func schedule(_ notification: LocalNotification) throws {
        scheduled[notification.id] = notification
    }

    public func cancel(id: String) { scheduled[id] = nil }
}

import ActivityKit
import Foundation

/// The part of ActivityKit the app needs (P038); a fake stands in for it in tests.
@MainActor
protocol LiveActivityService: AnyObject {
    /// False when the user turned Live Activities off for the app (or the device does not support them).
    var areActivitiesEnabled: Bool { get }
    /// Starts the activity for this workout, or updates it when it is already running.
    func upsert(_ attributes: WorkoutActivityAttributes, state: WorkoutActivityAttributes.ContentState, staleDate: Date?) async
    /// Ends the workout's activity. With `finalState` the summary stays on screen for `dismissAfter` seconds.
    func end(workoutId: UUID, finalState: WorkoutActivityAttributes.ContentState?, dismissAfter: TimeInterval) async
    /// Ends every activity that does not belong to `workoutId`: leftovers of a crashed app or a finished workout.
    func endAll(except workoutId: UUID?) async
}

@MainActor
final class ActivityKitLiveActivityService: LiveActivityService {
    private typealias WorkoutActivity = Activity<WorkoutActivityAttributes>
    private typealias Content = ActivityContent<WorkoutActivityAttributes.ContentState>

    var areActivitiesEnabled: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }

    func upsert(_ attributes: WorkoutActivityAttributes, state: WorkoutActivityAttributes.ContentState, staleDate: Date?) async {
        let content = ActivityContent(state: state, staleDate: staleDate)
        if await Self.update(workoutId: attributes.workoutId, content: content) { return }
        // Not allowed or too many activities: silently skip, the workout does not depend on it.
        _ = try? WorkoutActivity.request(attributes: attributes, content: content, pushType: nil)
    }

    func end(workoutId: UUID, finalState: WorkoutActivityAttributes.ContentState?, dismissAfter: TimeInterval) async {
        let content = finalState.map { ActivityContent(state: $0, staleDate: nil) }
        let policy: ActivityUIDismissalPolicy = finalState == nil ? .immediate : .after(.now + dismissAfter)
        await Self.finish(matching: { $0 == workoutId }, content: content, policy: policy)
    }

    func endAll(except workoutId: UUID?) async {
        await Self.finish(matching: { $0 != workoutId }, content: nil, policy: .immediate)
    }

    // `Activity` is not Sendable, so it never leaves these nonisolated helpers.

    private nonisolated static func update(workoutId: UUID, content: Content) async -> Bool {
        guard let running = WorkoutActivity.activities.first(where: { $0.attributes.workoutId == workoutId }) else {
            return false
        }
        await running.update(content)
        return true
    }

    private nonisolated static func finish(
        matching matches: @Sendable (UUID) -> Bool, content: Content?, policy: ActivityUIDismissalPolicy
    ) async {
        for activity in WorkoutActivity.activities where matches(activity.attributes.workoutId) {
            await activity.end(content, dismissalPolicy: policy)
        }
    }
}

/// Records calls instead of talking to ActivityKit.
@MainActor
final class FakeLiveActivityService: LiveActivityService {
    enum Call: Equatable {
        case upsert(WorkoutActivityAttributes.ContentState)
        case end(UUID, summary: Bool)
        case endAll(except: UUID?)
    }

    var areActivitiesEnabled: Bool
    private(set) var calls: [Call] = []
    private(set) var attributes: WorkoutActivityAttributes?
    private(set) var staleDate: Date?

    init(enabled: Bool = true) { areActivitiesEnabled = enabled }

    func upsert(_ attributes: WorkoutActivityAttributes, state: WorkoutActivityAttributes.ContentState, staleDate: Date?) async {
        self.attributes = attributes
        self.staleDate = staleDate
        calls.append(.upsert(state))
    }

    func end(workoutId: UUID, finalState: WorkoutActivityAttributes.ContentState?, dismissAfter: TimeInterval) async {
        calls.append(.end(workoutId, summary: finalState != nil))
    }

    func endAll(except workoutId: UUID?) async {
        calls.append(.endAll(except: workoutId))
    }
}

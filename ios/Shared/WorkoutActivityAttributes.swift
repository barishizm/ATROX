import ActivityKit
import Foundation

/// The workout Live Activity (P038). Compiled into the app and the widget extension.
///
/// Nothing here ticks: the elapsed time is drawn by the system from `startedAt`, and the rest countdown from
/// `restStart…restEnd`, so the app only sends an update when the *content* changes (set, exercise, rest start/stop).
struct WorkoutActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// Exercise being worked on right now.
        var exerciseName: String
        /// 1-based number of the set in progress and how many sets the exercise has ("Bench Press · 2/4").
        var setNumber: Int
        var setCount: Int
        /// Whole workout, for the summary.
        var completedSets: Int
        var totalSets: Int
        /// Rest countdown window; both nil when not resting.
        var restStart: Date?
        var restEnd: Date?
        /// Set when the workout is over: the activity then shows a summary instead of live data.
        var endedAt: Date?

        var isFinished: Bool { endedAt != nil }
    }

    let workoutId: UUID
    let workoutName: String
    let startedAt: Date
}

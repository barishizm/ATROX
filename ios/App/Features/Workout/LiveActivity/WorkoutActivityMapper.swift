import DataKit
import Foundation

/// Workout state → Live Activity content (P038). Pure, so every state can be tested.
enum WorkoutActivityMapper {
    typealias State = WorkoutActivityAttributes.ContentState

    static func attributes(for workout: WorkoutSnapshot, fallbackName: String) -> WorkoutActivityAttributes {
        let name = workout.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return WorkoutActivityAttributes(
            workoutId: workout.id, workoutName: name.isEmpty ? fallbackName : name, startedAt: workout.startedAt
        )
    }

    /// Live content of a running workout. The current exercise is the first one with an open set (the last one when
    /// everything is done); the current set is the first open one in it.
    static func state(
        workout: WorkoutSnapshot, rest: RestTimerController.Run?, now: Date, name: (ExerciseRef) -> String
    ) -> State {
        let exercises = workout.exercises
        let current = exercises.first { $0.sets.contains { !$0.input.isCompleted } } ?? exercises.last
        let sets = current?.sets ?? []
        let done = sets.filter(\.input.isCompleted).count
        let all = exercises.flatMap(\.sets)
        let activeRest = rest.flatMap { $0.endsAt > now ? $0 : nil }
        return State(
            exerciseName: current.map { name($0.ref) } ?? "",
            setNumber: sets.isEmpty ? 0 : min(done + 1, sets.count), setCount: sets.count,
            completedSets: all.filter(\.input.isCompleted).count, totalSets: all.count,
            restStart: activeRest?.startedAt, restEnd: activeRest?.endsAt, endedAt: nil
        )
    }

    /// The summary the activity shows when the workout is over.
    static func finalState(of state: State, endedAt: Date) -> State {
        var final = state
        final.restStart = nil
        final.restEnd = nil
        final.endedAt = endedAt
        return final
    }

    /// When the system should call the content stale: the moment the rest runs out, so the countdown disappears
    /// even if the app is suspended and cannot send another update.
    static func staleDate(for state: State) -> Date? { state.restEnd }
}

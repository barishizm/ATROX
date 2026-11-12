import Foundation

/// The part of Apple Health the workout flow needs (P041). `HealthService` in the app extends it.
public protocol HealthWorkoutWriting: Sendable {
    /// Writes a strength-training workout and returns its Health UUID; `nil` when Health is unavailable or not
    /// allowed. `id` is the app's workout id: writing the same one twice must not create a second Health workout.
    func saveWorkout(id: UUID, start: Date, end: Date) async -> UUID?
    /// Removes a workout written earlier. Returns whether nothing is left in Health afterwards.
    @discardableResult
    func deleteWorkout(uuid: UUID) async -> Bool
}

/// Keeps Apple Health and the local workout in step: one Health workout per finished workout, removed when the
/// workout is deleted, written again when a delete is undone.
public struct WorkoutHealthRecorder: Sendable {
    private let workouts: any WorkoutRepository
    private let health: any HealthWorkoutWriting

    public init(workouts: any WorkoutRepository, health: any HealthWorkoutWriting) {
        self.workouts = workouts
        self.health = health
    }

    /// Writes the finished workout to Health unless that already happened. Returns the Health UUID, if any.
    @discardableResult
    public func record(workoutId: UUID) async -> UUID? {
        guard let workout = try? await workouts.workout(id: workoutId), let end = workout.endedAt else { return nil }
        if let existing = workout.healthKitUUID { return existing }
        guard let uuid = await health.saveWorkout(id: workout.id, start: workout.startedAt, end: end) else { return nil }
        try? await workouts.setHealthKitUUID(id: workout.id, uuid: uuid)
        return uuid
    }

    /// Deletes the workout's Health record (if any) and forgets its UUID. Call before the workout is deleted.
    public func remove(workoutId: UUID) async {
        guard let workout = try? await workouts.workout(id: workoutId), let uuid = workout.healthKitUUID else { return }
        if await health.deleteWorkout(uuid: uuid) { try? await workouts.setHealthKitUUID(id: workout.id, uuid: nil) }
    }
}

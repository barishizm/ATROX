import Foundation

/// "Turn into a routine" (P042): a finished workout becomes a one-day routine whose targets come from what was done.
public enum RoutineConverter {
    /// Targets of one exercise from its sets: working sets (completed, not warm-up) give the set count and the rep
    /// range; RIR is the lowest logged one. An exercise without working sets gets the defaults.
    public static func targets(of exercise: WorkoutExerciseSnapshot) -> RoutineExerciseInput {
        let working = exercise.sets.map(\.input).filter { $0.setType != .warmup && $0.isCompleted }
        let reps = working.map(\.reps).filter { $0 > 0 }
        return RoutineExerciseInput(
            targetSets: min(max(working.count, 1), 50), targetRepsMin: reps.min(), targetRepsMax: reps.max(),
            targetRir: working.compactMap(\.rir).min(), supersetGroup: exercise.supersetGroup
        )
    }

    /// Creates the routine named `name` with a single day (named like the workout, else `dayName`).
    @discardableResult
    public static func convert(
        _ workout: WorkoutSnapshot, name: String, dayName: String, userId: UUID, routines: any RoutineRepository
    ) async throws -> RoutineSnapshot {
        let created = try await routines.create(name: name, notes: nil, userId: userId)
        let day = try await routines.addDay(routineId: created.id, name: workout.name ?? dayName)
        for exercise in workout.exercises {
            try await routines.addExercise(dayId: day.id, ref: exercise.ref, input: targets(of: exercise))
        }
        guard let result = try await routines.routine(id: created.id) else { throw DataError.notFound }
        return result
    }
}

import Foundation

enum WorkoutRoute: Hashable, Sendable {
    case activeWorkout(id: UUID)
    case exerciseLibrary
    case exerciseDetail(id: String)
    case routines
    case templates
    case routine(id: UUID)
    case routineDay(routineId: UUID, dayId: UUID)
    case history
    case workoutDetail(id: UUID)
    case exerciseHistory(id: String)
}

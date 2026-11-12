import Foundation

enum WorkoutRoute: Hashable, Sendable {
    case activeWorkout(id: UUID)
    case exerciseLibrary
    case exerciseDetail(id: String)
}

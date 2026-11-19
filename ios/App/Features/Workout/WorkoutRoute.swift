import Foundation

enum WorkoutRoute: Hashable, Sendable {
    case exerciseLibrary
    case exerciseDetail(id: String)
    case routines
    case create
    case templates
    case routine(id: UUID)
    case routineDay(routineId: UUID, dayId: UUID)
    case history
    case today
    case weeklySummary
    case workoutDetail(id: UUID)
    case exerciseHistory(id: String)
}

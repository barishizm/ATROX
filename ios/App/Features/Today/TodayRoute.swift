import Foundation

enum TodayRoute: Hashable, Sendable {
    case workoutSummary(id: UUID)
    case exerciseScore(catalogId: String)
    case templates
    case weeklySummary
}

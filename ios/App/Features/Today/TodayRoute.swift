import Foundation

enum TodayRoute: Hashable, Sendable {
    case exerciseScore(catalogId: String)
    case templates
    case weeklySummary
}

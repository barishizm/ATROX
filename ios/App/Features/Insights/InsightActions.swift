import DataKit
import Foundation
import Observation

/// What happens when the action button of an insight card is tapped. One instance per screen that shows cards; the
/// screen presents `suggestions` as a sheet and handles `openExercise`.
@MainActor
@Observable
final class InsightActions {
    struct Suggestion: Identifiable, Equatable {
        let id: String
        let name: String
    }

    struct SuggestionSheet: Identifiable, Equatable {
        let id: UUID
        let title: String
        let suggestions: [Suggestion]
    }

    var sheet: SuggestionSheet?

    func perform(_ item: InsightItem, container: AppContainer, openExercise: (String) -> Void) async {
        switch item.insight.action {
        case .suggestExercises:
            let picks = await container.insightSuggestions(muscles: item.insight.payload.muscles)
            sheet = SuggestionSheet(id: item.id, title: item.title, suggestions: picks.map { Suggestion(id: $0.id, name: $0.name) })
        case .askCoach:
            container.pendingCoachPrompt = item.coachPrompt
            container.requestedTab = .coach
        case .updateBodyweight:
            container.requestedTab = .profile
        case .viewExercise:
            if let id = item.insight.payload.subjects.first { openExercise(id) }
        case .startWorkout:
            container.requestedTab = .workout
        }
    }
}

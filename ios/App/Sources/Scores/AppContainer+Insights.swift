import DataKit
import Foundation
import SwiftData

/// Insight wiring of the composition root (P069).
extension AppContainer {
    /// The insight service of the signed-in user's store; created on first use. nil without a local store.
    func insightService() -> InsightService? {
        if let insightServiceState { return insightServiceState }
        guard let modelContainer, let scoreService else { return nil }
        let service = InsightService(
            modelContainer: modelContainer, scores: scoreService, stats: TrainingStats(modelContainer: modelContainer)
        )
        insightServiceState = service
        return service
    }

    func makeInsightsModel() async -> InsightsModel? {
        guard let service = insightService(), let context = await makeHistoryContext() else { return nil }
        _ = await scoreCenter()
        return InsightsModel(context: context, service: service)
    }

    /// Catalog exercises that train `muscles` (named in the app language), for "Add a ... exercise".
    func insightSuggestions(muscles: [String], limit: Int = 4) async -> [(id: String, name: String)] {
        guard let modelContainer else { return [] }
        let languageCode = language.effectiveLocale().language.languageCode?.identifier == "tr" ? "tr" : "en"
        let items = ((try? ModelContext(modelContainer).fetch(FetchDescriptor<Exercise>())) ?? []).filter { !$0.isArchived }.map(ExerciseListItem.init)
        return InsightSuggestions.pick(from: items, muscles: muscles, limit: limit, languageCode: languageCode)
            .map { ($0.id, $0.name(languageCode: languageCode)) }
    }
}

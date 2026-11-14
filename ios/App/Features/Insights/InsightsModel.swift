import DataKit
import Foundation
import Observation

/// Insight list state of the Analysis tab (P069): what is true now, and the history of dismissed or past insights.
@MainActor
@Observable
final class InsightsModel {
    private(set) var isLoading = true
    private(set) var current: [InsightItem] = []
    private(set) var history: [InsightItem] = []

    let context: HistoryContext
    @ObservationIgnored private let service: InsightService

    init(context: HistoryContext, service: InsightService) {
        self.context = context
        self.service = service
    }

    func load() async {
        let names = await context.loadNames()
        _ = await service.refresh(userId: context.userId)
        let userId = context.userId, locale = context.locale
        current = await service.current(userId: userId).map { InsightPresenter.item(for: $0, names: names, locale: locale) }
        history = await service.history(userId: userId).map { InsightPresenter.item(for: $0, names: names, locale: locale) }
        isLoading = false
    }

    func dismiss(_ item: InsightItem) async {
        await service.dismiss(id: item.id)
        current.removeAll { $0.id == item.id }
        await load()
    }
}

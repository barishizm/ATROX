import DataKit
import Foundation
import Observation
import SwiftData

/// State of the exercise library (P030): the catalog as light value items, the search text, filters, the favorite /
/// recent lists and the multi-select used when adding exercises to a program or workout.
@MainActor
@Observable
final class LibraryModel {
    enum LoadState: Equatable { case loading, loaded, failed }

    enum SectionKind: String { case recent, favorites, all, results }

    struct Section: Identifiable, Equatable {
        let kind: SectionKind
        let items: [ExerciseListItem]
        var id: String { kind.rawValue }
    }

    static let recentShown = 8

    private(set) var loadState: LoadState = .loading
    private(set) var sections: [Section] = []
    private(set) var selectionOrder: [String] = []
    /// True while the equipment filter is the automatic one derived from the user's equipment access.
    private(set) var isEquipmentSuggestion = false

    var query = "" { didSet { if query != oldValue { refresh() } } }
    var filter = ExerciseFilter() {
        didSet {
            if filter != oldValue { refresh() }
            if filter.equipment != suggestedFilter.equipment { isEquipmentSuggestion = false }
        }
    }
    /// "tr" / "en"; names and A–Z order follow it.
    var languageCode = "en" { didSet { if languageCode != oldValue { refresh() } } }

    let lists: ExerciseLists
    private let modelContainer: ModelContainer
    private let equipmentAccess: EquipmentAccess
    private var items: [ExerciseListItem] = []
    private var byID: [String: ExerciseListItem] = [:]

    init(modelContainer: ModelContainer, equipmentAccess: EquipmentAccess = .fullGym, lists: ExerciseLists = ExerciseLists()) {
        self.modelContainer = modelContainer
        self.equipmentAccess = equipmentAccess
        self.lists = lists
    }

    var suggestedFilter: ExerciseFilter { .suggested(for: equipmentAccess) }
    var hasEquipmentSuggestion: Bool { suggestedFilter.isActive }
    var totalCount: Int { items.count }
    var resultCount: Int { sections.reduce(0) { $0 + $1.items.count } }
    var availableEquipment: [String] {
        Array(Set(items.map { $0.equipment ?? ExerciseFilter.noEquipmentToken })).sorted()
    }

    func load() async {
        loadState = .loading
        do {
            let context = ModelContext(modelContainer)
            var descriptor = FetchDescriptor<Exercise>(predicate: #Predicate { !$0.isArchived })
            descriptor.sortBy = [SortDescriptor(\.id)]
            items = try context.fetch(descriptor).map(ExerciseListItem.init)
            byID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
            if hasEquipmentSuggestion {
                filter = suggestedFilter
                isEquipmentSuggestion = true
            }
            loadState = .loaded
            refresh()
        } catch {
            loadState = .failed
        }
    }

    // MARK: Filters

    func useSuggestedEquipment() {
        filter.equipment = suggestedFilter.equipment
        isEquipmentSuggestion = hasEquipmentSuggestion
    }

    func clearFilters() {
        filter = ExerciseFilter()
        isEquipmentSuggestion = false
    }

    // MARK: Favorites

    func toggleFavorite(_ id: String) {
        lists.toggleFavorite(id)
        refresh()
    }

    // MARK: Selection

    var selectionCount: Int { selectionOrder.count }
    func isSelected(_ id: String) -> Bool { selectionOrder.contains(id) }

    func toggleSelection(_ id: String) {
        if let index = selectionOrder.firstIndex(of: id) { selectionOrder.remove(at: index) } else { selectionOrder.append(id) }
    }

    /// Records the picked exercises as recently used and returns them in the order they were tapped.
    func confirmSelection() -> [String] {
        let picked = selectionOrder
        lists.noteUsed(picked)
        selectionOrder = []
        refresh()
        return picked
    }

    // MARK: Derived lists

    func refresh() {
        guard loadState == .loaded else { return }
        let filtered = items.filter(filter.matches)
        if !query.trimmingCharacters(in: .whitespaces).isEmpty {
            sections = [Section(kind: .results, items: ExerciseSearch.rank(query: query, in: filtered))]
            return
        }
        let allowed = Set(filtered.map(\.id))
        let recent = lists.recentIDs.prefix(Self.recentShown).filter(allowed.contains).compactMap { byID[$0] }
        let favorites = lists.favoriteIDs.filter(allowed.contains).compactMap { byID[$0] }
            .sorted { sortKey($0) < sortKey($1) }
        let all = filtered.sorted { sortKey($0) < sortKey($1) }
        sections = [
            Section(kind: .recent, items: recent),
            Section(kind: .favorites, items: favorites),
            Section(kind: .all, items: all),
        ].filter { !$0.items.isEmpty }
    }

    private func sortKey(_ item: ExerciseListItem) -> String {
        SearchFolding.fold(item.name(languageCode: languageCode))
    }
}

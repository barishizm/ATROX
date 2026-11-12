import DataKit
import Foundation
import SwiftData
import Testing
@testable import ATROX

@MainActor
@Suite struct LibraryModelTests {
    private func record(_ id: String, en: String, tr: String, equipment: String?, muscle: String, scoring: String = "weighted") -> CatalogRecord {
        CatalogRecord(
            id: id, equipment: equipment, primaryMuscles: [muscle], scoringType: scoring,
            translations: ["en": .init(name: en), "tr": .init(name: tr)])
    }

    private func makeModel(access: EquipmentAccess = .fullGym) async throws -> LibraryModel {
        let container = try DataStore.inMemory()
        let package = CatalogPackage(version: 1, checksum: "t", exercises: [
            record("bench", en: "Bench Press", tr: "Bench Press", equipment: "barbell", muscle: "chest"),
            record("pushup", en: "Push-Up", tr: "Şınav", equipment: "body_only", muscle: "chest"),
            record("plank", en: "Plank", tr: "Plank", equipment: nil, muscle: "abdominals", scoring: "none"),
            record("curl", en: "Curl", tr: "Pazı Bükme", equipment: "dumbbell", muscle: "biceps"),
        ])
        try await CatalogService(modelContainer: container, bundled: { package }).bootstrap()
        let defaults = UserDefaults(suiteName: "lib-\(UUID().uuidString)")!
        let model = LibraryModel(modelContainer: container, equipmentAccess: access, lists: ExerciseLists(defaults: defaults))
        await model.load()
        return model
    }

    @Test func fullGymStartsUnfilteredWithOnlyAllSection() async throws {
        let model = try await makeModel()
        #expect(!model.filter.isActive)
        #expect(model.sections.map(\.kind) == [.all])
        #expect(model.resultCount == 4)
    }

    @Test func bodyweightAccessSuggestsEquipmentFilterThatCanBeCleared() async throws {
        let model = try await makeModel(access: .bodyweightOnly)
        #expect(model.isEquipmentSuggestion)
        #expect(Set(model.sections.flatMap(\.items).map(\.id)) == ["pushup", "plank"])
        model.clearFilters()
        #expect(model.resultCount == 4)
        #expect(!model.isEquipmentSuggestion)
    }

    @Test func manualFilterChangeDropsTheSuggestionFlag() async throws {
        let model = try await makeModel(access: .bodyweightOnly)
        model.filter.scorableOnly = true
        #expect(model.isEquipmentSuggestion)   // equipment part still the suggestion
        model.filter.equipment = ["barbell"]
        #expect(!model.isEquipmentSuggestion)
    }

    @Test func searchFoldsAccentsAndFlattensIntoResults() async throws {
        let model = try await makeModel()
        model.query = "sinav"
        #expect(model.sections.map(\.kind) == [.results])
        #expect(model.sections.first?.items.map(\.id) == ["pushup"])
    }

    @Test func filtersCombineWithSearch() async throws {
        let model = try await makeModel()
        model.filter.muscles = ["chest"]
        model.filter.scorableOnly = true
        #expect(Set(model.sections.flatMap(\.items).map(\.id)) == ["bench", "pushup"])
        model.query = "bench"
        #expect(model.sections.first?.items.map(\.id) == ["bench"])
    }

    @Test func favoritesAndRecentsGetTheirOwnSectionsFirst() async throws {
        let model = try await makeModel()
        model.toggleFavorite("curl")
        model.toggleSelection("bench")
        _ = model.confirmSelection()
        #expect(model.sections.map(\.kind) == [.recent, .favorites, .all])
        #expect(model.sections[0].items.map(\.id) == ["bench"])
        #expect(model.sections[1].items.map(\.id) == ["curl"])
    }

    @Test func multiSelectKeepsTapOrderAndConfirmClearsIt() async throws {
        let model = try await makeModel()
        model.toggleSelection("curl"); model.toggleSelection("bench"); model.toggleSelection("plank")
        model.toggleSelection("bench")
        #expect(model.selectionCount == 2)
        #expect(model.confirmSelection() == ["curl", "plank"])
        #expect(model.selectionCount == 0)
        #expect(model.lists.recentIDs.first == "plank")
    }

    @Test func allSectionFollowsTheLanguageOrder() async throws {
        let model = try await makeModel()
        model.languageCode = "tr"
        #expect(model.sections.last?.items.first?.nameTr == "Bench Press")
        #expect(model.sections.last?.items.map(\.id) == ["bench", "plank", "curl", "pushup"])
    }
}

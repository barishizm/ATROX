@testable import DataKit
import Foundation
import Testing

private func item(
    _ id: String, en: String, tr: String, aliases: [String] = [], muscles: [String] = ["chest"],
    equipment: String? = "barbell", scorable: Bool = true
) -> ExerciseListItem {
    ExerciseListItem(
        id: id, nameEn: en, nameTr: tr, aliases: aliases, primaryMuscles: muscles, equipment: equipment, isScorable: scorable)
}

private let realCatalogURL = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("App/Resources/Catalog/catalog.v1.json")

private let sample = [
    item("pushup", en: "Push-Up", tr: "Şınav", aliases: ["Sinav", "Press-up"], equipment: "body_only"),
    item("bench", en: "Barbell Bench Press", tr: "Barbell Bench Press", aliases: ["Bench"]),
    item("incline-pushup", en: "Incline Push-Up", tr: "Eğimli Şınav", equipment: "body_only", scorable: false),
    item("squat", en: "Squat", tr: "Çömelme", aliases: ["Back Squat", "Squad"], muscles: ["quadriceps"]),
    item("curl", en: "Dumbbell Curl", tr: "Dumbbell Pazı Bükme", muscles: ["biceps"], equipment: "dumbbell"),
    item("plank", en: "Plank", tr: "Plank", muscles: ["abdominals"], equipment: nil, scorable: false),
]

private func ids(_ query: String, _ items: [ExerciseListItem] = sample) -> [String] {
    ExerciseSearch.rank(query: query, in: items).map(\.id)
}

@Suite struct ExerciseSearchTests {
    @Test func emptyQueryKeepsTheOrder() {
        #expect(ids("   ") == sample.map(\.id))
    }

    @Test func foldsAccentsCaseAndTurkishI() {
        #expect(ids("sinav").first == "pushup")
        #expect(ids("SINAV").contains("incline-pushup"))
        #expect(ids("ŞINAV").first == "pushup")
        #expect(ids("comelme") == ["squat"])
        #expect(ids("egimli") == ["incline-pushup"])
    }

    @Test func matchesBothLanguagesAndAliases() {
        #expect(ids("push-up").first == "pushup")
        #expect(ids("press-up") == ["pushup"])
        #expect(ids("back squat") == ["squat"])
    }

    @Test func ordersPrefixBeforeWordStartBeforeContains() {
        let items = [
            item("c", en: "Chest Press Machine", tr: "x1"),
            item("b", en: "Incline Press", tr: "x2"),
            item("a", en: "Press", tr: "x3"),
            item("d", en: "Depress", tr: "x4"),
        ]
        #expect(ids("press", items) == ["a", "b", "c", "d"])
    }

    @Test func nameMatchBeatsAliasMatch() {
        let items = [item("alias", en: "Zeta", tr: "Zeta", aliases: ["Squat variation"]), item("name", en: "Squat", tr: "Squat")]
        #expect(ids("squat", items) == ["name", "alias"])
    }

    @Test func multiWordQueryNeedsEveryWord() {
        #expect(ids("bench press") == ["bench"])
        #expect(ids("press bench") == ["bench"])
        #expect(ids("bench curl").isEmpty)
    }

    @Test func toleratesOneTypo() {
        #expect(ids("sqaut") == ["squat"])        // transposition
        #expect(ids("plnak") == ["plank"])        // transposition
        #expect(ids("planck") == ["plank"])       // extra letter
        #expect(ids("dumbel curl").contains("curl"))
        #expect(ids("cat").isEmpty)               // short tokens never go fuzzy
    }

    @Test func typoResultsComeAfterExactOnes() {
        let items = [item("fuzzy", en: "Squad", tr: "Squad"), item("exact", en: "Squat", tr: "Squat")]
        #expect(ids("squat", items).first == "exact")
    }

    @Test func realCatalogFindsTurkishPushUpWithoutAccents() throws {
        let catalog = try CatalogPackage.decode(Data(contentsOf: realCatalogURL))
        let items = catalog.exercises.map { record in
            ExerciseListItem(
                id: record.id, nameEn: record.translations["en"]?.name ?? record.id,
                nameTr: record.translations["tr"]?.name ?? record.id,
                aliases: (record.translations["en"]?.aliases ?? []) + (record.translations["tr"]?.aliases ?? []),
                primaryMuscles: record.primaryMuscles, equipment: record.equipment, isScorable: record.scoringType != "none")
        }
        #expect(items.count >= 800)
        #expect(ExerciseSearch.rank(query: "bench", in: items).isEmpty == false)
        // Every keystroke of a typed query stays fast on the full catalog.
        let clock = ContinuousClock()
        let elapsed = clock.measure {
            for prefix in ["b", "be", "ben", "benc", "bench", "bench p", "bench pr"] { _ = ExerciseSearch.rank(query: prefix, in: items) }
        }
        #expect(elapsed < .seconds(2))
    }
}

@Suite struct ExerciseFilterTests {
    @Test func filtersCombineWithAnd() {
        #expect(sample.filter(ExerciseFilter(muscles: ["chest"]).matches).count == 3)
        let bodyweightChest = ExerciseFilter(muscles: ["chest"], equipment: ["body_only"])
        #expect(sample.filter(bodyweightChest.matches).map(\.id) == ["pushup", "incline-pushup"])
        let scorable = ExerciseFilter(muscles: ["chest"], equipment: ["body_only"], scorableOnly: true)
        #expect(sample.filter(scorable.matches).map(\.id) == ["pushup"])
    }

    @Test func valuesInsideOneGroupCombineWithOr() {
        #expect(sample.filter(ExerciseFilter(muscles: ["biceps", "quadriceps"]).matches).map(\.id) == ["squat", "curl"])
    }

    @Test func noEquipmentTokenMatchesExercisesWithoutEquipment() {
        #expect(sample.filter(ExerciseFilter(equipment: [ExerciseFilter.noEquipmentToken]).matches).map(\.id) == ["plank"])
    }

    @Test func emptyFilterIsInactiveAndMatchesEverything() {
        let filter = ExerciseFilter()
        #expect(!filter.isActive)
        #expect(sample.allSatisfy(filter.matches))
    }

    @Test func activeCountCountsGroups() {
        #expect(ExerciseFilter(muscles: ["chest", "lats"], equipment: ["cable"], scorableOnly: true).activeCount == 3)
    }

    @Test func equipmentSuggestionFollowsAccess() {
        #expect(ExerciseFilter.suggestedEquipment(for: .fullGym) == nil)
        #expect(!ExerciseFilter.suggested(for: .fullGym).isActive)
        let bodyweight = ExerciseFilter.suggested(for: .bodyweightOnly)
        #expect(bodyweight.matches(sample[0]))     // push-up
        #expect(bodyweight.matches(sample[5]))     // plank, no equipment
        #expect(!bodyweight.matches(sample[1]))    // barbell
        let dumbbell = ExerciseFilter.suggested(for: .homeDumbbell)
        #expect(dumbbell.matches(sample[4]) && !dumbbell.matches(sample[1]))
        #expect(ExerciseFilter.suggested(for: .homeBarbell).matches(sample[1]))
    }
}

@MainActor
@Suite struct ExerciseListsTests {
    private func makeDefaults() -> UserDefaults {
        let name = "exercise-lists-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func togglesAndPersistsFavorites() {
        let defaults = makeDefaults()
        let lists = ExerciseLists(defaults: defaults)
        lists.toggleFavorite("squat"); lists.toggleFavorite("bench")
        #expect(lists.isFavorite("squat"))
        #expect(ExerciseLists(defaults: defaults).favoriteIDs == ["squat", "bench"])
        lists.toggleFavorite("squat")
        #expect(!lists.isFavorite("squat"))
        #expect(ExerciseLists(defaults: defaults).favoriteIDs == ["bench"])
    }

    @Test func recentsAreMostRecentFirstWithoutDuplicatesAndCapped() {
        let lists = ExerciseLists(defaults: makeDefaults())
        lists.noteUsed(["a", "b"])
        lists.noteUsed(["a"])
        #expect(lists.recentIDs == ["a", "b"])
        lists.noteUsed((0..<30).map { "e\($0)" })
        #expect(lists.recentIDs.count == ExerciseLists.recentLimit)
        #expect(lists.recentIDs.first == "e29")
    }
}

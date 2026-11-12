import DataKit
import Foundation
import SwiftData
import Testing

@testable import ATROX

@MainActor
@Suite struct ExerciseDetailAndCustomExerciseTests {
    private let user = UUID()

    private func makeStore() async throws -> ModelContainer {
        let container = try DataStore.inMemory()
        let bench = CatalogRecord(
            id: "bench", equipment: "barbell", mechanic: "compound", primaryMuscles: ["chest"], secondaryMuscles: ["triceps"],
            scoringType: "weighted", anchorLift: "bench", loadConvention: "total", ratio: 1, tau: 0.2,
            ratioConfidence: "A", images: ["a.f.webp", "b.f.webp"],
            translations: ["en": .init(name: "Bench Press", instructions: ["Lie down", "Press"]), "tr": .init(name: "Bench Press")])
        let package = CatalogPackage(version: 1, checksum: "t", exercises: [bench])
        try await CatalogService(modelContainer: container, bundled: { package }).bootstrap()
        return container
    }

    private func makeForm(_ container: ModelContainer) -> CustomExerciseFormModel {
        CustomExerciseFormModel(userId: user, repository: SwiftDataCustomExerciseRepository(modelContainer: container))
    }

    @Test func detailModelLoadsCatalogExerciseWithFramesAndFallbackSteps() async throws {
        let container = try await makeStore()
        let model = ExerciseDetailModel(id: "bench", modelContainer: container, userId: user)
        await model.load()
        let detail = try #require(model.detail)
        #expect(detail.frames == ["a.f.webp", "b.f.webp"])
        #expect(detail.instructions(languageCode: "tr") == ["Lie down", "Press"])
        #expect(!model.canManage)
    }

    @Test func unknownIdIsMissing() async throws {
        let model = ExerciseDetailModel(id: "nope", modelContainer: try await makeStore(), userId: user)
        await model.load()
        #expect(model.state == .missing)
    }

    @Test func formNeedsNameAndPrimaryMuscle() async throws {
        let form = makeForm(try await makeStore())
        #expect(!form.isValid)
        form.name = "  Cable Fly "
        #expect(!form.isValid)
        form.setPrimary(["chest"])
        #expect(form.isValid)
        form.name = "   "
        #expect(!form.isValid)
    }

    @Test func aMuscleIsNeverPrimaryAndSecondaryAtOnce() async throws {
        let form = makeForm(try await makeStore())
        form.setSecondary(["chest", "triceps"])
        form.setPrimary(["chest"])
        #expect(form.secondaryMuscles == ["triceps"])
        form.setSecondary(["chest", "lats"])
        #expect(form.secondaryMuscles == ["lats"])
    }

    @Test func similarExercisePrefillsEmptyFieldsAndInheritsScoring() async throws {
        let container = try await makeStore()
        let form = makeForm(container)
        form.name = "My Bench"
        let source = try #require(try ExerciseDetail.load(id: "bench", in: container))
        form.setSimilar(source)
        #expect(form.primaryMuscles == ["chest"])
        #expect(form.equipment == "barbell")
        let input = form.input()
        #expect(input.scoring.type == "weighted")
        #expect(input.scoring.anchorLift == "bench")
        form.setSimilar(nil)
        #expect(form.input().scoring.type == "none")
    }

    @Test func similarKeepsWhatTheUserAlreadyChose() async throws {
        let container = try await makeStore()
        let form = makeForm(container)
        form.equipment = "cable"
        form.setPrimary(["lats"])
        let source = try #require(try ExerciseDetail.load(id: "bench", in: container))
        form.setSimilar(source)
        #expect(form.equipment == "cable")
        #expect(form.primaryMuscles == ["lats"])
    }

    @Test func savedCustomExerciseAppearsInTheLibraryAndSearchFindsIt() async throws {
        let container = try await makeStore()
        let form = makeForm(container)
        form.name = "Çapraz Kablo"
        form.setPrimary(["chest"])
        form.stepsText = "Pull\n\nSqueeze "
        let saved = try #require(await form.save())
        #expect(saved.input.instructions == ["Pull", "Squeeze"])

        let defaults = UserDefaults(suiteName: "p031-\(UUID().uuidString)")!
        let library = LibraryModel(modelContainer: container, userId: user, lists: ExerciseLists(defaults: defaults))
        await library.load()
        #expect(library.totalCount == 2)
        library.query = "capraz"
        let hit = try #require(library.sections.flatMap(\.items).first)
        #expect(hit.isCustom && hit.id == saved.id.uuidString)

        // Another user's library does not show it; catalog-only mode hides it too.
        let other = LibraryModel(modelContainer: container, userId: UUID(), lists: ExerciseLists(defaults: defaults))
        await other.load()
        #expect(other.totalCount == 1)
        let catalogOnly = LibraryModel(modelContainer: container, userId: user, catalogOnly: true, lists: ExerciseLists(defaults: defaults))
        await catalogOnly.load()
        #expect(catalogOnly.totalCount == 1)
        #expect(catalogOnly.filter.scorableOnly)
        #expect(!catalogOnly.canCreateCustom)
    }

    @Test func customExerciseCanBeEditedAndDeletedFromDetail() async throws {
        let container = try await makeStore()
        let create = makeForm(container)
        create.name = "Mine"
        create.setPrimary(["biceps"])
        let saved = try #require(await create.save())

        let detail = ExerciseDetailModel(id: saved.id.uuidString, modelContainer: container, userId: user)
        await detail.load()
        #expect(detail.canManage)
        let snapshot = try #require(await detail.customSnapshot())
        let edit = CustomExerciseFormModel(userId: user, repository: detail.customRepository, editing: snapshot)
        #expect(edit.name == "Mine")
        edit.name = "Mine 2"
        _ = try #require(await edit.save())
        await detail.load()
        #expect(detail.detail?.nameEn == "Mine 2")

        #expect(await detail.delete())
        await detail.load()
        #expect(detail.state == .missing)
    }

    @Test func didCreateCustomClearsFiltersThatWouldHideIt() async throws {
        let container = try await makeStore()
        let defaults = UserDefaults(suiteName: "p031-\(UUID().uuidString)")!
        let library = LibraryModel(
            modelContainer: container, equipmentAccess: .bodyweightOnly, userId: user, lists: ExerciseLists(defaults: defaults))
        await library.load()
        let form = makeForm(container)
        form.name = "Cable Thing"
        form.equipment = "cable"
        form.setPrimary(["chest"])
        let saved = try #require(await form.save())
        library.didCreateCustom(id: saved.id.uuidString, select: true)
        #expect(!library.filter.isActive)
        #expect(library.isSelected(saved.id.uuidString))
        #expect(library.sections.flatMap(\.items).contains { $0.id == saved.id.uuidString })
    }
}

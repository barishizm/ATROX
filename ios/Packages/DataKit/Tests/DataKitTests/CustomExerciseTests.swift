@testable import DataKit
import Foundation
import SwiftData
import Testing

private func input(_ name: String = "Cable Fly", muscles: [String] = ["chest"]) -> CustomExerciseInput {
    CustomExerciseInput(name: name, equipment: "cable", primaryMuscles: muscles)
}

@Suite struct CustomExerciseRepositoryTests {
    private func makeRepo(_ clock: TestClock = TestClock()) throws -> SwiftDataCustomExerciseRepository {
        SwiftDataCustomExerciseRepository(modelContainer: try DataStore.inMemory(), clock: clock.closure)
    }

    @Test func createdExerciseIsPendingAndUnscoredByDefault() async throws {
        let clock = TestClock()
        let repo = try makeRepo(clock)
        let saved = try await repo.create(input("  Cable Fly  "), userId: testUser)
        #expect(saved.input.name == "Cable Fly")
        #expect(saved.syncState == .pending)
        #expect(saved.input.scoring == .none)
        #expect(saved.createdAt == clock.now)
        #expect(try await repo.exercise(id: saved.id) == saved)
    }

    @Test func updateTouchesUpdatedAtAndKeepsCreatedAt() async throws {
        let clock = TestClock()
        let repo = try makeRepo(clock)
        let saved = try await repo.create(input(), userId: testUser)
        clock.advance(by: 60)
        var changed = saved.input
        changed.name = "Pec Fly"
        changed.secondaryMuscles = ["shoulders", "chest"]
        let updated = try await repo.update(id: saved.id, with: changed)
        #expect(updated.input.name == "Pec Fly")
        #expect(updated.input.secondaryMuscles == ["shoulders"], "a primary muscle is dropped from the secondary list")
        #expect(updated.createdAt == saved.createdAt)
        #expect(updated.updatedAt == clock.now)
        #expect(updated.syncState == .pending)
    }

    @Test func deleteIsSoftAndHidesTheRow() async throws {
        let clock = TestClock()
        let repo = try makeRepo(clock)
        let saved = try await repo.create(input(), userId: testUser)
        try await repo.delete(id: saved.id)
        #expect(try await repo.exercise(id: saved.id) == nil)
        #expect(try await repo.all(userId: testUser).isEmpty)
        await #expect(throws: DataError.notFound) { try await repo.delete(id: saved.id) }
    }

    @Test func allIsPerUserAndSortedByName() async throws {
        let repo = try makeRepo()
        _ = try await repo.create(input("Zottman Curl", muscles: ["biceps"]), userId: testUser)
        _ = try await repo.create(input("Arnold Press", muscles: ["shoulders"]), userId: testUser)
        _ = try await repo.create(input("Other"), userId: otherUser)
        #expect(try await repo.all(userId: testUser).map(\.input.name) == ["Arnold Press", "Zottman Curl"])
    }

    @Test func rejectsInvalidInput() async throws {
        let repo = try makeRepo()
        await #expect(throws: DataError.invalidValue("name")) { try await repo.create(input("   "), userId: testUser) }
        await #expect(throws: DataError.invalidValue("name")) {
            try await repo.create(input(String(repeating: "x", count: 201)), userId: testUser)
        }
        await #expect(throws: DataError.invalidValue("primaryMuscles")) {
            try await repo.create(input(muscles: []), userId: testUser)
        }
        await #expect(throws: DataError.invalidValue("primaryMuscles")) {
            try await repo.create(input(muscles: ["lower back"]), userId: testUser)
        }
        var bad = input()
        bad.equipment = "cables"
        await #expect(throws: DataError.invalidValue("equipment")) { try await repo.create(bad, userId: testUser) }
        bad = input()
        bad.scoring.loadConvention = "x"
        await #expect(throws: DataError.invalidValue("loadConvention")) { try await repo.create(bad, userId: testUser) }
    }

    @Test func similarExerciseScoringIsCopied() async throws {
        let container = try DataStore.inMemory()
        let bench = CatalogRecord(
            id: "barbell-bench-press", equipment: "barbell", primaryMuscles: ["chest"], scoringType: "weighted",
            anchorLift: "bench", loadConvention: "total", ratio: 1, tau: 0.2, ratioConfidence: "A",
            translations: ["en": .init(name: "Bench Press")]
        )
        let context = ModelContext(container)
        context.insert(Exercise(record: bench))
        try context.save()
        let source = try #require(try ExerciseDetail.load(id: "barbell-bench-press", in: container))
        var form = input("My Bench")
        form.scoring = source.scoring
        let repo = SwiftDataCustomExerciseRepository(modelContainer: container, clock: { Date() })
        let saved = try await repo.create(form, userId: testUser)
        #expect(saved.input.scoring.type == "weighted")
        #expect(saved.input.scoring.anchorLift == "bench")
        #expect(saved.input.scoring.ratio == 1)
    }

    @Test func customExerciseIsFoundByTheLibrarySearchAndLoadsAsDetail() async throws {
        let container = try DataStore.inMemory()
        let repo = SwiftDataCustomExerciseRepository(modelContainer: container, clock: { Date() })
        let saved = try await repo.create(input("Çapraz Kablo Açış"), userId: testUser)
        let context = ModelContext(container)
        let items = try context.fetch(FetchDescriptor<CustomExercise>()).map(ExerciseListItem.init)
        #expect(items.first?.isCustom == true)
        #expect(ExerciseSearch.rank(query: "capraz", in: items).map(\.id) == [saved.id.uuidString])

        let detail = try #require(try ExerciseDetail.load(id: saved.id.uuidString, in: container))
        #expect(detail.isCustom)
        #expect(detail.name(languageCode: "tr") == "Çapraz Kablo Açış")
        #expect(detail.scoreNote == .notScored)
        try await repo.delete(id: saved.id)
        #expect(try ExerciseDetail.load(id: saved.id.uuidString, in: container) == nil)
    }
}

@Suite struct ExerciseDetailTests {
    @Test func scoreNoteFollowsTheScoringType() {
        func note(_ scoring: ScoringSettings, _ equipment: String? = "barbell") -> ScoreNote? {
            ScoreNote.note(for: scoring, equipment: equipment)
        }
        #expect(note(.none) == .notScored)
        #expect(note(ScoringSettings(type: "reps_only")) == .repsOnly)
        #expect(note(ScoringSettings(type: "time")) == .time)
        #expect(note(ScoringSettings(type: "weighted", ratioConfidence: "A")) == nil)
        #expect(note(ScoringSettings(type: "weighted", ratioConfidence: "A"), "machine") == .machine)
        #expect(note(ScoringSettings(type: "weighted", loadConvention: "machine_stack"), "cable") == .machine)
        #expect(note(ScoringSettings(type: "weighted", ratioConfidence: "C")) == .lowConfidence)
        #expect(note(ScoringSettings(type: "bodyweight_loaded", ratioConfidence: "B"), nil) == .bodyweightLoaded)
    }

    @Test func instructionsFallBackToTheOtherLanguage() {
        let detail = ExerciseDetail(
            id: "x", nameEn: "X", nameTr: "Y", instructionsEn: ["one", "two"], instructionsTr: [], primaryMuscles: ["chest"])
        #expect(detail.instructions(languageCode: "tr") == ["one", "two"])
        #expect(detail.instructions(languageCode: "en") == ["one", "two"])
        #expect(detail.name(languageCode: "tr") == "Y")
    }

    @Test func missingExerciseLoadsAsNil() throws {
        let container = try DataStore.inMemory()
        #expect(try ExerciseDetail.load(id: "nope", in: container) == nil)
        #expect(try ExerciseDetail.load(id: UUID().uuidString, in: container) == nil)
    }
}

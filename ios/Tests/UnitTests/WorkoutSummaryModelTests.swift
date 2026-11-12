import DataKit
import Foundation
import Testing

@testable import ATROX

private final class Clock: @unchecked Sendable {
    private let lock = NSLock()
    private var current = Date(timeIntervalSince1970: 1_800_000_000)
    var now: Date { lock.withLock { current } }
    func advance(_ seconds: TimeInterval) { lock.withLock { current = current.addingTimeInterval(seconds) } }
}

@MainActor
@Suite struct FinishPromptTests {
    private let bench = ExerciseRef.catalog("bench")

    private func makeModel(clock: Clock) async throws -> ActiveWorkoutModel {
        let repo = SwiftDataWorkoutRepository(modelContainer: try DataStore.inMemory())
        let session = WorkoutSession(userId: UUID(), workouts: repo, clock: { clock.now })
        try await session.startEmpty()
        _ = try await session.addExercise(bench)
        let model = ActiveWorkoutModel(session: session, unit: .kilograms, itemsProvider: { [] })
        await model.load()
        return model
    }

    /// Completes every set the exercise starts with.
    private func completeFirstSet(_ model: ActiveWorkoutModel) async throws {
        for setId in try #require(model.session.workout?.exercises.first?.sets.map(\.id)) {
            try await model.session.setReps(setId, reps: 5)
            try await model.session.setWeight(setId, kg: 60)
            try await model.session.completeSet(setId)
        }
    }

    @Test func emptyWorkoutOnlyOffersDiscard() async throws {
        let clock = Clock()
        let model = try await makeModel(clock: clock)
        clock.advance(3600)
        #expect(model.finishPrompt() == .empty)
    }

    @Test func shortWorkoutAsksBeforeSaving() async throws {
        let clock = Clock()
        let model = try await makeModel(clock: clock)
        try await completeFirstSet(model)
        clock.advance(60)
        #expect(model.finishPrompt() == .short(open: 0))
    }

    @Test func openSetsAreOfferedForDeletion() async throws {
        let clock = Clock()
        let model = try await makeModel(clock: clock)
        try await completeFirstSet(model)
        let exerciseId = try #require(model.session.workout?.exercises.first?.id)
        try await model.session.addSet(to: exerciseId)
        clock.advance(1800)
        #expect(model.finishPrompt() == .openSets(1))
    }

    @Test func completedLongWorkoutJustConfirms() async throws {
        let clock = Clock()
        let model = try await makeModel(clock: clock)
        try await completeFirstSet(model)
        clock.advance(1800)
        #expect(model.finishPrompt() == .confirm)
    }

    @Test func summaryRecordsKeepOnlyHitsOfSetsStillCompleted() async throws {
        let clock = Clock()
        let model = try await makeModel(clock: clock)
        try await completeFirstSet(model)
        let workout = try #require(model.session.workout)
        let kept = try #require(workout.exercises.first?.sets.first?.id)
        model.recordHits = [
            PersonalRecordHit(ref: bench, kind: .weight, value: 60, setId: kept),
            PersonalRecordHit(ref: bench, kind: .weight, value: 99, setId: UUID()),
        ]
        #expect(model.summaryRecords(for: workout).map(\.setId) == [kept])
    }
}

@MainActor
@Suite struct WorkoutSummaryModelTests {
    private let user = UUID()
    private let bench = ExerciseRef.catalog("bench")

    private func finishedWorkout(repo: SwiftDataWorkoutRepository, start: Date, kg: Double) async throws -> WorkoutSnapshot {
        let started = try await repo.start(
            WorkoutDraft(startedAt: start, exercises: [
                WorkoutExerciseDraft(ref: bench, sets: [SetInput(weightKg: kg, reps: 10, isCompleted: true)]),
            ]),
            userId: user
        )
        return try await repo.finish(id: started.id, at: start.addingTimeInterval(1800))
    }

    private func makeModel(
        unit: ATROX.WeightUnit = .kilograms, previousKg: Double? = nil
    ) async throws -> (WorkoutSummaryModel, SwiftDataWorkoutRepository) {
        let repo = SwiftDataWorkoutRepository(modelContainer: try DataStore.inMemory())
        let day = Date(timeIntervalSince1970: 1_800_000_000)
        var previous: WorkoutSnapshot?
        if let previousKg { previous = try await finishedWorkout(repo: repo, start: day, kg: previousKg) }
        let workout = try await finishedWorkout(repo: repo, start: day.addingTimeInterval(86_400), kg: 100)
        let summary = WorkoutSummary(
            workout: workout, previous: previous, muscles: [bench: ExerciseMuscles(primary: ["chest"], secondary: ["triceps"])],
            records: [PersonalRecordHit(ref: bench, kind: .weight, value: 100, setId: UUID())]
        )
        let model = WorkoutSummaryModel(
            workout: workout, summary: summary, unit: unit, names: [bench: "Bench Press"], repository: repo,
            decimalSeparator: ","
        )
        return (model, repo)
    }

    @Test func showsVolumeDurationAndRecords() async throws {
        let (model, _) = try await makeModel()
        #expect(model.volumeText == "1000")
        #expect(model.durationText == "30:00")
        #expect(model.recordRows.map(\.exercise) == ["Bench Press"])
        #expect(model.recordRows.first?.valueText == "100 kg")
    }

    @Test func volumeFollowsTheDisplayUnit() async throws {
        let (model, _) = try await makeModel(unit: .pounds)
        #expect(model.volumeText == "2204,6")
        #expect(model.recordRows.first?.valueText.hasSuffix("lb") == true)
    }

    @Test func volumeChangeIsShownAgainstThePreviousWorkout() async throws {
        let (first, _) = try await makeModel()
        #expect(first.volumeChange == nil)
        let (second, _) = try await makeModel(previousKg: 80)
        let change = try #require(second.volumeChange)
        #expect(change.direction == .up)
        #expect(change.text == "+200 kg (+25 %)")
    }

    @Test func muscleIntensitiesAreNormalisedToOne() async throws {
        let (model, _) = try await makeModel()
        let values = model.muscleIntensities.values.sorted()
        #expect(values == [0.5, 1])
    }

    @Test func saveStoresNameNoteAndFeeling() async throws {
        let (model, repo) = try await makeModel()
        model.name = "  Push day "
        model.notes = "Felt strong"
        model.rating = 4
        #expect(await model.save())
        let stored = try #require(try await repo.workout(id: model.workout.id))
        #expect(stored.name == "Push day")
        #expect(stored.notes == "Felt strong")
        #expect(stored.rating == 4)
        model.name = "   "
        model.rating = nil
        #expect(await model.save())
        let cleared = try #require(try await repo.workout(id: model.workout.id))
        #expect(cleared.name == nil && cleared.rating == nil)
    }
}

@Suite struct FakeHealthWorkoutTests {
    @Test func fakeHealthWritesOncePerWorkoutAndDeletes() async {
        let health = FakeHealthService()
        let id = UUID()
        let first = await health.saveWorkout(id: id, start: .now, end: .now.addingTimeInterval(60))
        let second = await health.saveWorkout(id: id, start: .now, end: .now.addingTimeInterval(60))
        #expect(first != nil && first == second)
        #expect(await health.workouts.count == 1)
        #expect(await health.deleteWorkout(uuid: first!))
        #expect(await health.workouts.isEmpty)
    }

    @Test func unavailableHealthWritesNothing() async {
        let health = UnavailableHealthService()
        #expect(await health.saveWorkout(id: UUID(), start: .now, end: .now) == nil)
    }

    @Test func fakeHealthWithoutPermissionWritesNothing() async {
        let health = FakeHealthService(authorizationGranted: false)
        #expect(await health.saveWorkout(id: UUID(), start: .now, end: .now) == nil)
    }
}

import DataKit
import Foundation
import StrengthKit
import Testing

@testable import ATROX

@Suite struct WorkoutKeypadTests {
    @Test func firstDigitReplacesThePrefilledValueThenAppends() {
        var pad = WorkoutKeypad(field: .weight, value: 80)
        #expect(pad.text == "80")
        pad.digit(1)
        pad.digit(0)
        pad.digit(5)
        #expect(pad.text == "105")
    }

    @Test func decimalAndBackspace() {
        var pad = WorkoutKeypad(field: .weight, value: 80)
        pad.decimal()
        #expect(pad.text == "0.")
        pad.digit(5)
        pad.decimal()
        #expect(pad.text == "0.5")
        pad.backspace()
        pad.backspace()
        #expect(pad.text == "0")
        #expect(pad.value == 0)
    }

    @Test func repsHaveNoDecimalMark() {
        var pad = WorkoutKeypad(field: .reps, value: 8)
        pad.decimal()
        #expect(pad.text == "8")
        #expect(WorkoutKeypad(field: .reps, value: 7.6).text == "8")
    }

    @Test func stepsMoveByThePlateStepAndStopAtZero() {
        var pad = WorkoutKeypad(field: .weight, value: 1)
        pad.step(1, by: 2.5)
        #expect(pad.text == "3.5")
        pad.step(-1, by: 2.5)
        pad.step(-1, by: 2.5)
        #expect(pad.value == 0)
    }

    @Test func lengthIsCappedAndLeadingZeroReplaced() {
        var pad = WorkoutKeypad(field: .reps, value: 0)
        for _ in 0..<10 { pad.digit(1) }
        #expect(pad.text.count == WorkoutKeypad.maxLength)
        var zero = WorkoutKeypad(field: .reps, value: 0)
        zero.backspace()
        zero.digit(0)
        zero.digit(7)
        #expect(zero.text == "7")
    }

    @Test func displayUsesTheLocaleSeparator() {
        let pad = WorkoutKeypad(field: .weight, value: 82.5)
        #expect(pad.displayText(decimalSeparator: ",") == "82,5")
    }
}

@MainActor
@Suite struct ActiveWorkoutModelTests {
    private let user = UUID()
    private let bench = ExerciseRef.catalog("bench")
    private let items = [
        ExerciseListItem(id: "bench", nameEn: "Bench Press", nameTr: "Bench Press", primaryMuscles: ["chest"]),
        ExerciseListItem(id: "fly", nameEn: "Cable Fly", nameTr: "Kablo Fly", primaryMuscles: ["chest"]),
    ]

    private func makeModel(unit: ATROX.WeightUnit = .kilograms) async throws -> ActiveWorkoutModel {
        let repo = SwiftDataWorkoutRepository(modelContainer: try DataStore.inMemory())
        let session = WorkoutSession(userId: user, workouts: repo)
        try await session.startEmpty()
        _ = try await session.addExercise(bench)
        let entries = items.map { ActiveWorkoutModel.CatalogEntry(item: $0, pattern: "push") }
        let model = ActiveWorkoutModel(session: session, unit: unit, itemsProvider: { entries })
        await model.load()
        return model
    }

    @Test func suggestionTextLeadsWithTheTargetInTheDisplayUnit() async throws {
        let kg = try await makeModel()
        let up = ProgressionSuggestion(weightKg: 62.5, reps: 8, rationale: .addWeight(incrementKg: 2.5))
        #expect(kg.suggestionText(for: up).contains("62.5 kg × 8"))
        #expect(kg.suggestionText(for: up).contains("2.5 kg"))
        let bodyweight = ProgressionSuggestion(weightKg: 0, reps: 11, rationale: .addRepBodyweight)
        #expect(!kg.suggestionText(for: bodyweight).contains("kg"))
        let lb = try await makeModel(unit: .pounds)
        let step = ProgressionSuggestion(weightKg: 100.0 * 0.45359237, reps: 5, rationale: .deload)
        #expect(lb.suggestionText(for: step).contains("100 lb × 5"))
    }

    @Test func cardsCarryTheSessionsSuggestionOnlyWhenThereIsOne() async throws {
        let model = try await makeModel()
        #expect(model.cards.first?.suggestionText == nil)
    }

    @Test func rowsShowBadgesAndNames() async throws {
        let model = try await makeModel()
        let card = try #require(model.cards.first)
        #expect(card.name == "Bench Press")
        #expect(card.rows.map(\.badge) == ["1", "2", "3"])
        let first = try #require(card.rows.first)
        await model.setType(first.id, .warmup)
        #expect(model.cards[0].rows.map(\.badge) == ["W", "1", "2"])
    }

    @Test func typingWeightThenRepsThenCompletingPersists() async throws {
        let model = try await makeModel()
        let first = try #require(model.cards.first?.rows.first)
        await model.beginEditing(first.id, field: .weight)
        for digit in [8, 2] { model.press(digit: digit) }
        model.pressDecimal()
        model.press(digit: 5)
        await model.advance()
        #expect(model.editing?.keypad.field == .reps)
        model.press(digit: 6)
        await model.advance()
        #expect(model.editing?.setId != first.id, "moves on to the next set")
        await model.toggleComplete(first.id)
        let stored = try #require(model.session.set(first.id)).input
        #expect(stored.weightKg == 82.5 && stored.reps == 6 && stored.isCompleted)
    }

    @Test func poundsAreStoredAsKilograms() async throws {
        let model = try await makeModel(unit: .pounds)
        let first = try #require(model.cards.first?.rows.first)
        await model.beginEditing(first.id, field: .weight)
        model.press(digit: 2)
        model.press(digit: 2)
        model.press(digit: 0)
        await model.dismissKeypad()
        let kg = try #require(model.session.set(first.id)).input.weightKg
        #expect(abs(kg - 99.79) < 0.01)
        #expect(model.cards[0].rows[0].weightText == "220")
    }

    @Test func completingAcceptsPrefilledValuesWithOneTapAndTogglesBack() async throws {
        let model = try await makeModel()
        let first = try #require(model.cards.first?.rows.first)
        await model.toggleComplete(first.id)
        #expect(model.cards[0].rows[0].isCompleted)
        #expect(model.completedSetCount == 1)
        await model.toggleComplete(first.id)
        #expect(model.completedSetCount == 0)
    }

    @Test func sameAsPreviousCopiesTheSetAbove() async throws {
        let model = try await makeModel()
        let rows = try #require(model.cards.first?.rows)
        await model.beginEditing(rows[0].id, field: .weight)
        model.press(digit: 6)
        model.press(digit: 0)
        await model.dismissKeypad()
        await model.beginEditing(rows[1].id, field: .weight)
        model.pressSameAsPrevious()
        #expect(model.editing?.keypad.text == "60")
    }

    @Test func similarExercisesSkipWhatIsAlreadyInTheWorkout() async throws {
        let model = try await makeModel()
        #expect(model.similarExercises(to: bench).map(\.id) == ["fly"])
    }

    @Test func removingASetClosesItsKeypad() async throws {
        let model = try await makeModel()
        let first = try #require(model.cards.first?.rows.first)
        await model.beginEditing(first.id, field: .reps)
        await model.removeSet(first.id)
        #expect(model.editing == nil)
        #expect(model.cards[0].rows.count == 2)
    }
}

@MainActor
@Suite struct ActiveWorkoutRestTests {
    private let user = UUID()
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func makeModel(mechanic: String?, autoStart: Bool = true, sets: Int = 3) async throws -> (
        ActiveWorkoutModel, FakeNotificationService
    ) {
        let repo = SwiftDataWorkoutRepository(modelContainer: try DataStore.inMemory())
        let session = WorkoutSession(userId: user, workouts: repo)
        try await session.startEmpty()
        let exerciseId = try await session.addExercise(.catalog("bench"))
        while (session.exercise(exerciseId)?.sets.count ?? 0) > sets, let last = session.exercise(exerciseId)?.sets.last {
            try await session.removeSet(last.id)
        }
        let service = FakeNotificationService(status: .authorized)
        let rest = RestTimerController(clock: { Date(timeIntervalSince1970: 1_800_000_000) }, notifications: service)
        let entry = ActiveWorkoutModel.CatalogEntry(
            item: ExerciseListItem(id: "bench", nameEn: "Bench Press", nameTr: "Bench Press", primaryMuscles: ["chest"]),
            pattern: "push", mechanic: mechanic
        )
        let model = ActiveWorkoutModel(
            session: session, unit: .kilograms, autoStartsRest: autoStart, rest: rest, itemsProvider: { [entry] }
        )
        await model.load()
        return (model, service)
    }

    @Test func completingASetStartsTheRestForItsMovementType() async throws {
        let (compound, _) = try await makeModel(mechanic: "compound")
        await compound.toggleComplete(try #require(compound.cards.first?.rows.first).id)
        #expect(compound.rest.remaining() == 120)

        let (isolation, _) = try await makeModel(mechanic: "isolation")
        await isolation.toggleComplete(try #require(isolation.cards.first?.rows.first).id)
        #expect(isolation.rest.remaining() == 75)

        let (unknown, _) = try await makeModel(mechanic: nil)
        await unknown.toggleComplete(try #require(unknown.cards.first?.rows.first).id)
        #expect(unknown.rest.remaining() == 90)
    }

    @Test func noRestAfterTheLastOpenSetOrWhenAutoStartIsOff() async throws {
        let (single, _) = try await makeModel(mechanic: "compound", sets: 1)
        await single.toggleComplete(try #require(single.cards.first?.rows.first).id)
        #expect(!single.rest.isRunning)

        let (off, _) = try await makeModel(mechanic: "compound", autoStart: false)
        await off.toggleComplete(try #require(off.cards.first?.rows.first).id)
        #expect(!off.rest.isRunning)
    }

    @Test func undoingASetDoesNotStartARest() async throws {
        let (model, _) = try await makeModel(mechanic: "compound")
        let id = try #require(model.cards.first?.rows.first).id
        await model.toggleComplete(id)
        await model.rest.skip()
        await model.toggleComplete(id)
        #expect(!model.rest.isRunning)
    }

    @Test func finishingOrCancellingStopsTheRest() async throws {
        let (model, service) = try await makeModel(mechanic: "compound")
        await model.toggleComplete(try #require(model.cards.first?.rows.first).id)
        #expect(model.rest.isRunning)
        await model.cancel()
        #expect(!model.rest.isRunning)
        #expect(await service.scheduled.isEmpty)
    }
}

@MainActor
@Suite struct WarmupAndPlateTests {
    private let user = UUID()
    private let squat = ExerciseRef.catalog("squat")

    private func makeModel(unit: ATROX.WeightUnit = .kilograms) async throws -> (ActiveWorkoutModel, UUID) {
        let repo = SwiftDataWorkoutRepository(modelContainer: try DataStore.inMemory())
        let session = WorkoutSession(userId: user, workouts: repo)
        try await session.startEmpty()
        let exerciseId = try await session.addExercise(squat)
        let item = ExerciseListItem(id: "squat", nameEn: "Squat", nameTr: "Squat", primaryMuscles: ["quads"], equipment: "barbell")
        let model = ActiveWorkoutModel(session: session, unit: unit, itemsProvider: { [.init(item: item, pattern: "squat")] })
        await model.load()
        return (model, exerciseId)
    }

    private func defaults() -> UserDefaults {
        let suite = "warmup-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test func previewNeedsAWorkingWeight() async throws {
        let (model, id) = try await makeModel()
        #expect(model.warmupPreview(forExercise: id, defaults: defaults()).isEmpty)
    }

    @Test func addingWarmupsPutsThemFirstAndLeavesWorkingSets() async throws {
        let (model, id) = try await makeModel()
        let first = try #require(model.cards.first?.rows.first)
        await model.applyPlateWeight(first.id, displayWeight: 100)
        let prefs = defaults()
        #expect(model.warmupPreview(forExercise: id, defaults: prefs).map(\.weight) == [20, 40, 60, 80])

        await model.addWarmups(to: id, defaults: prefs)
        let rows = try #require(model.cards.first?.rows)
        #expect(rows.count == 7)
        #expect(rows.prefix(4).map(\.badge) == ["W", "W", "W", "W"])
        #expect(rows.prefix(4).map(\.weightText) == ["20", "40", "60", "80"])
        #expect(rows.prefix(4).map(\.repsText) == ["10", "8", "5", "3"])
        #expect(rows[4].weightText == "100")
        #expect(rows.allSatisfy { !$0.isCompleted })
    }

    @Test func poundsRoundToFivePoundsAndStoreKilograms() async throws {
        let (model, id) = try await makeModel(unit: .pounds)
        let first = try #require(model.cards.first?.rows.first)
        await model.applyPlateWeight(first.id, displayWeight: 225)
        await model.addWarmups(to: id, defaults: defaults())
        let sets = try #require(model.session.exercise(id)?.sets)
        #expect(sets.prefix(4).map { Int(ATROX.WeightUnit.pounds.value(fromKilograms: $0.input.weightKg).rounded()) } == [45, 90, 135, 180])
    }

    @Test func customBarAndOwnedPlatesComeFromPreferences() {
        let prefs = defaults()
        #expect(PlatePreferences.barWeight(unit: .kilograms, defaults: prefs) == 20)
        #expect(PlatePreferences.ownedPlates(unit: .kilograms, defaults: prefs) == [25, 20, 15, 10, 5, 2.5, 1.25])
        prefs.set(BarType.ez.rawValue, forKey: PlatePreferences.barTypeKey)
        #expect(PlatePreferences.barWeight(unit: .pounds, defaults: prefs) == 20)
        prefs.set(BarType.custom.rawValue, forKey: PlatePreferences.barTypeKey)
        prefs.set(10.0, forKey: PlatePreferences.customBarKgKey)
        #expect(PlatePreferences.barWeight(unit: .kilograms, defaults: prefs) == 10)
        prefs.set(PlatePreferences.encode([20, 5]), forKey: PlatePreferences.ownedKey(.kilograms))
        #expect(PlatePreferences.ownedPlates(unit: .kilograms, defaults: prefs) == [20, 5])
    }
}

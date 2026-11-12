import DataKit
import Foundation
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

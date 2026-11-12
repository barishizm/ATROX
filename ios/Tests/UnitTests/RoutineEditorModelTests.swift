import DataKit
import Foundation
import SwiftData
import Testing

@testable import ATROX

@MainActor
@Suite struct RoutineEditorModelTests {
    private let user = UUID()
    private let items = [
        ExerciseListItem(id: "bench", nameEn: "Bench Press", nameTr: "Bench Press", primaryMuscles: ["chest"], secondaryMuscles: ["triceps"]),
        ExerciseListItem(id: "row", nameEn: "Row", nameTr: "Kürek", primaryMuscles: ["lats"]),
    ]

    private func makeModel() async throws -> (RoutineEditorModel, UUID) {
        let repo = SwiftDataRoutineRepository(modelContainer: try DataStore.inMemory(), clock: { Date() })
        let routine = try await repo.create(name: "PPL", notes: nil, userId: user)
        let defaults = UserDefaults(suiteName: "routine-\(UUID().uuidString)")!
        let plan = RoutinePlanStore(userId: user, defaults: defaults)
        let provided = items
        let model = RoutineEditorModel(routineId: routine.id, repository: repo, plan: plan) { provided }
        await model.load()
        return (model, routine.id)
    }

    @Test func threeDayProgramIsBuiltAndPersisted() async throws {
        let (model, _) = try await makeModel()
        for name in ["Push", "Pull", "Legs"] { _ = await model.addDay(name: name) }
        let push = try #require(model.routine?.days.first).id
        await model.addExercises(dayId: push, itemIDs: ["bench", "row"])
        #expect(model.routine?.days.map(\.name) == ["Push", "Pull", "Legs"])
        #expect(model.routine?.days[0].exercises.map { model.name(of: $0.ref) } == ["Bench Press", "Row"])
        #expect(model.emptyDays.map(\.name) == ["Pull", "Legs"])
        #expect(model.weeklySets.first(where: { $0.muscle == "chest" })?.sets == 3)
    }

    @Test func undoPutsTheProgramBack() async throws {
        let (model, _) = try await makeModel()
        let day = try #require(await model.addDay(name: "Push"))
        await model.addExercises(dayId: day, itemIDs: ["bench"])
        #expect(model.canUndo)
        await model.deleteDay(day)
        #expect(model.routine?.days.isEmpty == true)
        await model.undo()
        #expect(model.routine?.days.first?.exercises.count == 1)
        await model.undo()  // takes the exercise away again
        #expect(model.routine?.days.first?.exercises.isEmpty == true)
    }

    @Test func supersetsGetLettersAndSurviveReload() async throws {
        let (model, _) = try await makeModel()
        let day = try #require(await model.addDay(name: "Push"))
        await model.addExercises(dayId: day, itemIDs: ["bench", "row", "bench"])
        let exercises = try #require(model.day(day)).exercises
        await model.makeSuperset([exercises[0].id, exercises[1].id])
        await model.load()
        let updated = try #require(model.day(day))
        #expect(model.supersetLetter(of: updated.exercises[0], in: updated) == "A")
        #expect(model.supersetLetter(of: updated.exercises[1], in: updated) == "A")
        #expect(model.supersetLetter(of: updated.exercises[2], in: updated) == nil)
    }

    @Test func reorderIsPersisted() async throws {
        let (model, _) = try await makeModel()
        let day = try #require(await model.addDay(name: "Push"))
        await model.addExercises(dayId: day, itemIDs: ["bench", "row"])
        await model.moveExercises(dayId: day, from: IndexSet(integer: 0), to: 2)
        await model.load()
        #expect(model.day(day)?.exercises.map { model.name(of: $0.ref) } == ["Row", "Bench Press"])
    }

    @Test func weekdayPlanAndActiveProgram() async throws {
        let (model, routineId) = try await makeModel()
        let day = try #require(await model.addDay(name: "Push"))
        model.assign(dayId: day, toWeekday: 2)
        #expect(model.weekdayPlan(2) == .day(day) && model.weekdayPlan(3) == .rest)
        model.assign(dayId: UUID(), toWeekday: 4)
        #expect(model.weekdayPlan(4) == .elsewhere)
        model.setActive(true)
        #expect(model.isActive && model.plan.activeRoutineId == routineId)
    }

    @Test func itemIdsMapToCatalogOrCustomRefs() {
        let custom = UUID()
        #expect(RoutineEditorModel.ref(fromItemID: "bench") == .catalog("bench"))
        #expect(RoutineEditorModel.ref(fromItemID: custom.uuidString) == .custom(custom))
        #expect(RoutineEditorModel.id(of: .custom(custom)) == custom.uuidString)
        #expect(RoutineEditorModel.defaultDayName(2, languageCode: "tr") == "Gün 2")
        #expect(RoutineEditorModel.defaultDayName(2, languageCode: "en") == "Day 2")
    }
}

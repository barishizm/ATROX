import CoachKit
import DataKit
import Foundation
import SwiftData
import Testing

@testable import ATROX

@Suite struct MarkdownBlocksTests {
    @Test func parsesParagraphsListsHeadingsAndCode() {
        let blocks = MarkdownBlocks.parse("""
        ## Plan
        First line
        second line

        - squat
        - press

        1. warm up
        2) lift

        ```
        3x5
        ```
        """)
        #expect(blocks == [
            .heading("Plan"), .paragraph("First line\nsecond line"), .bullets(["squat", "press"]),
            .numbered(["warm up", "lift"]), .code("3x5")
        ])
    }

    @Test func parsesATableWithoutItsSeparatorRow() {
        let blocks = MarkdownBlocks.parse("| Day | Focus |\n|---|:---:|\n| A | Legs |\n| B | Push |")
        #expect(blocks == [.table(header: ["Day", "Focus"], rows: [["A", "Legs"], ["B", "Push"]])])
    }

    @Test func plainTextAndUnfinishedMarkdownNeverCrash() {
        #expect(MarkdownBlocks.parse("").isEmpty)
        #expect(MarkdownBlocks.parse("**bold** and `code`") == [.paragraph("**bold** and `code`")])
        #expect(MarkdownBlocks.parse("```\nnever closed") == [.code("never closed")])
        #expect(MarkdownBlocks.parse("|just a pipe") == [.paragraph("|just a pipe")])
        #expect(MarkdownBlocks.parse("#hashtag") == [.paragraph("#hashtag")])
    }
}

@Suite struct CoachSuggestionsTests {
    private let locale = Locale(identifier: "en")

    @Test func alwaysFourQuestionsWithoutRepeats() {
        for facts in [
            CoachSuggestions.Facts(),
            CoachSuggestions.Facts(weakestMuscle: "chest", hasWorkouts: true, hasRoutine: true)
        ] {
            let list = CoachSuggestions.make(facts, locale: locale)
            #expect(list.count == 4 && Set(list).count == 4)
        }
    }

    @Test func questionsFollowTheUsersData() {
        let newcomer = CoachSuggestions.make(CoachSuggestions.Facts(), locale: locale)
        #expect(newcomer[0] == "Make me a 3-day-a-week program")
        let regular = CoachSuggestions.make(CoachSuggestions.Facts(weakestMuscle: "chest", hasWorkouts: true, hasRoutine: true), locale: locale)
        #expect(regular[0] == "Can you review my program?" && regular[1].lowercased().contains("chest"))
        #expect(regular.contains("How did my recent workouts go?"))
    }

    @Test func turkishQuestionsAreTurkish() {
        let list = CoachSuggestions.make(CoachSuggestions.Facts(), locale: Locale(identifier: "tr"))
        #expect(list[0] == "Haftada 3 gün için bir program hazırla")
    }
}

@Suite struct ProposalSummaryTests {
    private let locale = Locale(identifier: "en")

    private func routineProposal() -> CoachProposal {
        CoachProposal(id: "p", kind: .routine, data: .object([
            "name": .string("Starter"),
            "days": .array([
                .object(["name": .string("A"), "exercises": .array([
                    .object(["exercise_id": .string("goblet-squat"), "name": .string("Goblet Squat"), "sets": .number(3), "reps_min": .number(8), "reps_max": .number(12)])
                ])])
            ])
        ]), warnings: [.init(exerciseId: "goblet-squat", area: "knee")])
    }

    @Test func routineSummaryNamesDaysExercisesAndLimitationWarnings() {
        let summary = ProposalSummary.make(for: routineProposal(), locale: locale)
        #expect(summary.title == "Starter" && summary.subtitle == "1 days · 1 exercises")
        #expect(summary.days.first?.lines == ["Goblet Squat · 3×8–12"])
        #expect(summary.warnings == ["Goblet Squat: be careful with your knee"])
    }

    @Test func swapAndGoalCardsReadTheirData() {
        let swap = CoachProposal(id: "s", kind: .exerciseSwap, data: .object([
            "from": .object(["id": .string("a"), "name": .string("Back Squat")]),
            "to": .object(["id": .string("b"), "name": .string("Goblet Squat")]), "reason": .string("Knee pain")
        ]))
        #expect(ProposalSummary.make(for: swap, locale: locale).lines == ["Back Squat → Goblet Squat"])
        let goal = CoachProposal(id: "g", kind: .goalUpdate, data: .object(["goal": .string("strength"), "weekly_frequency": .number(4)]))
        #expect(ProposalSummary.make(for: goal, locale: locale).lines == ["Goal: Strength", "4 days per week"])
    }

    @Test func unknownKindsGetAnUpdateHintInsteadOfButtons() {
        let summary = ProposalSummary.make(for: CoachProposal(id: "u", kind: .unknown), locale: locale)
        #expect(summary.title == "Unsupported suggestion")
        #expect(CoachProposal(id: "u", kind: .unknown).needsDecision)
    }
}

@MainActor
@Suite struct ProposalApplierTests {
    private let user = UUID()
    private let routines: SwiftDataRoutineRepository
    private let profiles: SwiftDataProfileRepository
    private let applier: ProposalApplier
    private let activated = Box()

    final class Box: @unchecked Sendable {
        var active: UUID?
    }

    init() throws {
        let store = try DataStore.inMemory()
        routines = SwiftDataRoutineRepository(modelContainer: store)
        profiles = SwiftDataProfileRepository(modelContainer: store)
        let box = activated
        applier = ProposalApplier(
            userId: user, routines: routines, profiles: profiles,
            activeRoutineId: { box.active }, activate: { box.active = $0 }
        )
    }

    private func line(_ id: String, sets: Int = 3, low: Int = 8, high: Int = 12) -> CoachJSON {
        .object(["exercise_id": .string(id), "sets": .number(Double(sets)), "reps_min": .number(Double(low)), "reps_max": .number(Double(high))])
    }

    private func newRoutine() -> CoachProposal {
        CoachProposal(id: "r", kind: .routine, data: .object([
            "name": .string("3-day"), "notes": .string("coach"),
            "days": .array(["A", "B", "C"].map { name in
                .object(["name": .string(name), "exercises": .array([line("goblet-squat"), line("pushups", sets: 4, low: 10, high: 10)])])
            })
        ]))
    }

    @Test func applyingARoutineCreatesDaysAndExercisesAndActivatesTheFirstRoutine() async throws {
        let outcome = try await applier.apply(newRoutine())
        guard case .routineCreated(let id, let name) = outcome else {
            Issue.record("expected a created routine")
            return
        }
        #expect(name == "3-day" && activated.active == id)
        let routine = try #require(try await routines.routine(id: id))
        #expect(routine.days.map(\.name) == ["A", "B", "C"] && routine.exerciseCount == 6)
        let second = try #require(routine.days.first?.exercises.last)
        #expect(second.ref == .catalog("pushups") && second.input.targetSets == 4 && second.input.targetRepsMin == 10)
    }

    @Test func anExistingActiveRoutineIsNotReplaced() async throws {
        let existing = UUID()
        activated.active = existing
        _ = try await applier.apply(newRoutine())
        #expect(activated.active == existing)
    }

    @Test func aBrokenRoutineChangesNothing() async throws {
        let broken = CoachProposal(id: "b", kind: .routine, data: .object(["name": .string("x"), "days": .array([])]))
        await #expect(throws: ApplyError.invalidProposal) { try await applier.apply(broken) }
        #expect(try await routines.all(userId: user).isEmpty)
        await #expect(throws: ApplyError.invalidProposal) { try await applier.apply(CoachProposal(id: "m", kind: .memorySaved)) }
    }

    @Test func routineEditsAddRemoveReplaceAndUpdate() async throws {
        guard case .routineCreated(let id, _) = try await applier.apply(newRoutine()) else { return }
        let day = try #require(try await routines.routine(id: id)?.days.first).id
        let edit = CoachProposal(id: "e", kind: .routineEdit, data: .object([
            "routine_id": .string(id.uuidString),
            "operations": .array([
                .object(["op": .string("add"), "day_id": .string(day.uuidString), "exercise": line("dumbbell-bench-press")]),
                .object(["op": .string("update"), "day_id": .string(day.uuidString), "exercise_id": .string("goblet-squat"), "sets": .number(5)]),
                .object(["op": .string("replace"), "day_id": .string(day.uuidString), "exercise_id": .string("pushups"), "with": line("barbell-full-squat")]),
                .object(["op": .string("remove"), "day_id": .string(day.uuidString), "exercise_id": .string("dumbbell-bench-press")]),
                .object(["op": .string("remove"), "day_id": .string(day.uuidString), "exercise_id": .string("not-in-day")])
            ])
        ]))
        let outcome = try await applier.apply(edit)
        #expect(outcome == .routineChanged(id: id, changes: 4), "the operation on an exercise that is not on the day is skipped")
        let exercises = try #require(try await routines.routine(id: id)?.days.first).exercises
        #expect(exercises.map(\.ref) == [.catalog("goblet-squat"), .catalog("barbell-full-squat")], "replace keeps the old slot")
        #expect(exercises.first?.input.targetSets == 5)
        #expect(exercises.map(\.position) == [0, 1])
    }

    @Test func aSwapReplacesTheExerciseOnEveryDayOfTheRoutine() async throws {
        guard case .routineCreated(let id, _) = try await applier.apply(newRoutine()) else { return }
        let swap = CoachProposal(id: "s", kind: .exerciseSwap, data: .object([
            "from": .object(["id": .string("goblet-squat")]), "to": .object(["id": .string("barbell-full-squat")]),
            "routine_id": .string(id.uuidString)
        ]))
        #expect(try await applier.apply(swap) == .routineChanged(id: id, changes: 3))
        let days = try #require(try await routines.routine(id: id)).days
        #expect(days.allSatisfy { $0.exercises.map(\.ref) == [.catalog("barbell-full-squat"), .catalog("pushups")] })
    }

    @Test func aSwapWithoutAnyRoutineHasNothingToChange() async throws {
        let swap = CoachProposal(id: "s", kind: .exerciseSwap, data: .object([
            "from": .object(["id": .string("a")]), "to": .object(["id": .string("b")])
        ]))
        #expect(try await applier.apply(swap) == .nothingToChange)
    }

    @Test func aGoalUpdateChangesOnlyGoalAndFrequency() async throws {
        let birth = Calendar.current.date(byAdding: .year, value: -30, to: Date()) ?? Date()
        try await profiles.upsert(ProfileInput(firstName: "Ada", birthDate: birth, heightCm: 170, goal: .generalHealth, weeklyFrequency: 2), userId: user)
        let update = CoachProposal(id: "g", kind: .goalUpdate, data: .object(["goal": .string("muscle_gain"), "weekly_frequency": .number(4)]))
        #expect(try await applier.apply(update) == .goalUpdated)
        let saved = try #require(try await profiles.profile(userId: user)).input
        #expect(saved.goal == .muscleGain && saved.weeklyFrequency == 4 && saved.firstName == "Ada" && saved.heightCm == 170)
    }

    @Test func aGoalUpdateWithoutAProfileFailsCleanly() async throws {
        let update = CoachProposal(id: "g", kind: .goalUpdate, data: .object(["goal": .string("strength")]))
        await #expect(throws: ApplyError.profileMissing) { try await applier.apply(update) }
    }
}

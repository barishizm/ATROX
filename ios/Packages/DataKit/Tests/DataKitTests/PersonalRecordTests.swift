// swiftlint:disable large_tuple
@testable import DataKit
import Foundation
import SwiftData
import Testing

private let bench = ExerciseRef.catalog("barbell_bench_press")

@MainActor
@Suite struct PersonalRecordTests {
    private struct Env {
        let container: ModelContainer
        let clock: TestClock
        let workouts: SwiftDataWorkoutRepository
        let service: SwiftDataPersonalRecordService

        @MainActor
        func session() -> WorkoutSession {
            WorkoutSession(userId: testUser, workouts: workouts, records: service, clock: clock.closure)
        }

        func rows(kind: RecordKind? = nil) throws -> [PersonalRecord] {
            let all = try ModelContext(container).fetch(FetchDescriptor<PersonalRecord>())
                .filter { !$0.isSoftDeleted }
            return all.filter { kind == nil || $0.kind == kind }
        }
    }

    private func makeEnv() throws -> Env {
        let container = try DataStore.inMemory()
        let clock = TestClock()
        return Env(
            container: container, clock: clock,
            workouts: SwiftDataWorkoutRepository(modelContainer: container, clock: clock.closure),
            service: SwiftDataPersonalRecordService(modelContainer: container, clock: clock.closure)
        )
    }

    /// Trains one bench workout of working sets `(kg, reps)`, completing each; returns the hits per set and the workout id.
    @discardableResult
    private func train(
        _ env: Env, _ sets: [(Double, Int)], type: SetType = .working
    ) async throws -> (hits: [[PersonalRecordHit]], workoutId: UUID, setIds: [UUID]) {
        let session = env.session()
        try await session.startEmpty()
        let exerciseId = try await session.addExercise(bench)
        let workoutId = try #require(session.workout?.id)
        var ids = try #require(session.exercise(exerciseId)?.sets.map(\.id))
        while ids.count < sets.count { ids.append(try await session.addSet(to: exerciseId)) }
        var hits: [[PersonalRecordHit]] = []
        for (id, set) in zip(ids, sets) {
            try await session.setWeight(id, kg: set.0)
            try await session.setReps(id, reps: set.1)
            if type != .working { try await session.setType(id, to: type) }
            hits.append(try await session.completeSet(id))
        }
        try await session.finish()
        env.clock.advance(by: 86_400)
        return (hits, workoutId, Array(ids.prefix(sets.count)))
    }

    @Test func firstEverSetIsNotACelebratedRecord() async throws {
        let env = try makeEnv()
        let result = try await train(env, [(100, 5)])
        #expect(result.hits == [[]])
        #expect(try env.rows().count == 4)  // weight, e1rm, volume, reps are stored silently
    }

    @Test func laterHeavierSetBreaksRecordsAndStoresThem() async throws {
        let env = try makeEnv()
        try await train(env, [(100, 5)])
        let second = try await train(env, [(105, 5)])
        let kinds = Set(second.hits[0].map(\.kind))
        #expect(kinds == [.weight, .e1rm, .volume])
        let weightRow = try #require(env.rows(kind: .weight).first)
        #expect(weightRow.value == 105 && weightRow.setId == second.setIds[0])
        #expect(second.hits[0].first?.kind == .weight)
        #expect(second.hits[0].allSatisfy { !$0.needsConfirmation })
    }

    @Test func warmupAndTieSetsAreNotRecords() async throws {
        let env = try makeEnv()
        try await train(env, [(100, 5)])
        let warm = try await train(env, [(140, 5)], type: .warmup)
        #expect(warm.hits == [[]])
        let tie = try await train(env, [(100, 5)])
        #expect(tie.hits == [[]])
        #expect(try #require(env.rows(kind: .weight).first).value == 100)
    }

    @Test func bigE1rmJumpNeedsConfirmation() async throws {
        let env = try makeEnv()
        try await train(env, [(100, 5)])
        let jump = try await train(env, [(130, 5)])
        let e1rm = try #require(jump.hits[0].first { $0.kind == .e1rm })
        #expect(e1rm.needsConfirmation)
        #expect(try #require(jump.hits[0].first { $0.kind == .weight }).needsConfirmation == false)
    }

    @Test func historyBeforeTheEngineIsBootstrapped() async throws {
        // History saved without a record engine, then a record is broken with it.
        let env = try makeEnv()
        let plain = WorkoutSession(userId: testUser, workouts: env.workouts, clock: env.clock.closure)
        try await plain.startEmpty()
        let exerciseId = try await plain.addExercise(bench)
        let id = try #require(plain.exercise(exerciseId)?.sets.first?.id)
        try await plain.setWeight(id, kg: 100)
        try await plain.setReps(id, reps: 5)
        try await plain.completeSet(id)
        try await plain.finish()
        env.clock.advance(by: 86_400)
        #expect(try env.rows().isEmpty)
        let next = try await train(env, [(110, 5)])
        #expect(Set(next.hits[0].map(\.kind)).contains(.weight))
    }

    @Test func deletingTheRecordWorkoutFallsBackToThePreviousBest() async throws {
        let env = try makeEnv()
        let first = try await train(env, [(100, 5)])
        let second = try await train(env, [(110, 5)])
        #expect(try #require(env.rows(kind: .weight).first).value == 110)
        try await env.workouts.delete(id: second.workoutId)
        try await env.service.exerciseChanged(ref: bench, userId: testUser)
        let weight = try env.rows(kind: .weight)
        #expect(weight.count == 1)
        #expect(weight[0].value == 100 && weight[0].setId == first.setIds[0])
        // The next 105 is a record again.
        let again = try await train(env, [(105, 5)])
        #expect(Set(again.hits[0].map(\.kind)).contains(.weight))
    }

    @Test func editingASetInTheActiveWorkoutRebuildsRecords() async throws {
        let env = try makeEnv()
        try await train(env, [(100, 5)])
        let session = env.session()
        try await session.startEmpty()
        let exerciseId = try await session.addExercise(bench)
        let id = try #require(session.exercise(exerciseId)?.sets.first?.id)
        try await session.setWeight(id, kg: 110)
        try await session.setReps(id, reps: 5)
        let hits = try await session.completeSet(id)
        #expect(Set(hits.map(\.kind)).contains(.weight))
        #expect(try #require(env.rows(kind: .weight).first).value == 110)
        try await session.setWeight(id, kg: 102.5)
        #expect(try #require(env.rows(kind: .weight).first).value == 102.5)
        try await session.uncompleteSet(id)
        #expect(try #require(env.rows(kind: .weight).first).value == 100)
        try await session.completeSet(id)
        try await session.removeSet(id)
        #expect(try #require(env.rows(kind: .weight).first).value == 100)
    }

    @Test func recomputeIsStableAndIdempotent() async throws {
        let env = try makeEnv()
        try await train(env, [(100, 5), (100, 8)])
        try await train(env, [(105, 3)])
        let before = try env.rows().map { "\($0.kindRaw):\($0.value):\($0.setId?.uuidString ?? "")" }.sorted()
        try await env.service.exerciseChanged(ref: bench, userId: testUser)
        try await env.service.exerciseChanged(ref: bench, userId: testUser)
        let after = try env.rows().map { "\($0.kindRaw):\($0.value):\($0.setId?.uuidString ?? "")" }.sorted()
        #expect(before == after)
    }

    @Test func cancellingAWorkoutRemovesItsRecords() async throws {
        let env = try makeEnv()
        try await train(env, [(100, 5)])
        let session = env.session()
        try await session.startEmpty()
        let exerciseId = try await session.addExercise(bench)
        let id = try #require(session.exercise(exerciseId)?.sets.first?.id)
        try await session.setWeight(id, kg: 120)
        try await session.setReps(id, reps: 5)
        try await session.completeSet(id)
        #expect(try #require(env.rows(kind: .weight).first).value == 120)
        try await session.cancel()
        #expect(try #require(env.rows(kind: .weight).first).value == 100)
    }
}

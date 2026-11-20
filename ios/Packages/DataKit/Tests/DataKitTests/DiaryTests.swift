@testable import DataKit
import Foundation
import Testing

@Suite struct DiaryRepositoryTests {
    private let clock = TestClock()
    private let day = Date(timeIntervalSince1970: 1_800_000_000)

    private func makeRepo() throws -> SwiftDataDiaryRepository {
        SwiftDataDiaryRepository(modelContainer: try DataStore.inMemory(), clock: clock.closure)
    }

    private func water(_ ml: Double = 250, at date: Date) -> DiaryLogInput { DiaryLogInput(kind: .water, at: date, amount: ml) }

    @Test func addStoresPendingRow() async throws {
        let saved = try await makeRepo().add(water(at: day), userId: testUser)
        #expect(saved.syncState == .pending)
        #expect(saved.input.kind == .water)
        #expect(saved.input.amount == 250)
    }

    @Test func logsFilterByKindDayUserAndHideDeleted() async throws {
        let repo = try makeRepo()
        let first = try await repo.add(water(at: day), userId: testUser)
        _ = try await repo.add(water(at: day.addingTimeInterval(60)), userId: testUser)
        _ = try await repo.add(DiaryLogInput(kind: .note, at: day, label: "good"), userId: testUser)
        _ = try await repo.add(water(at: day), userId: otherUser)
        _ = try await repo.add(water(at: day.addingTimeInterval(86_400 * 2)), userId: testUser)
        let range = (day.addingTimeInterval(-60), day.addingTimeInterval(86_400))
        #expect(try await repo.logs(userId: testUser, kinds: [.water], from: range.0, to: range.1).count == 2)
        try await repo.delete(id: first.id)
        #expect(try await repo.logs(userId: testUser, kinds: [.water], from: range.0, to: range.1).count == 1)
        #expect(try await repo.logs(userId: testUser, kinds: [.water, .note], from: range.0, to: range.1).count == 2)
    }

    @Test func latestReturnsTheNewestOfAKind() async throws {
        let repo = try makeRepo()
        _ = try await repo.add(DiaryLogInput(kind: .goalWeight, at: day, amount: 80), userId: testUser)
        _ = try await repo.add(DiaryLogInput(kind: .goalWeight, at: day.addingTimeInterval(60), amount: 78), userId: testUser)
        #expect(try await repo.latest(userId: testUser, kind: .goalWeight)?.input.amount == 78)
        #expect(try await repo.latest(userId: testUser, kind: .fast) == nil)
    }

    @Test func updateMarksPending() async throws {
        let repo = try makeRepo()
        let saved = try await repo.add(DiaryLogInput(kind: .fast, at: day, quantity: 16, label: "16:8"), userId: testUser)
        clock.advance(by: 60)
        let ended = DiaryLogInput(kind: .fast, at: day, endedAt: day.addingTimeInterval(3600), quantity: 16, label: "16:8")
        let updated = try await repo.update(id: saved.id, with: ended)
        #expect(updated.input.endedAt != nil)
        #expect(updated.updatedAt > saved.updatedAt)
    }

    @Test func rejectsInvalidValues() async throws {
        let repo = try makeRepo()
        await #expect(throws: DataError.self) { try await repo.add(water(0, at: day), userId: testUser) }
        await #expect(throws: DataError.self) { try await repo.add(DiaryLogInput(kind: .goalWeight, at: day, amount: 5), userId: testUser) }
        await #expect(throws: DataError.self) { try await repo.add(DiaryLogInput(kind: .activity, at: day, quantity: 30), userId: testUser) }
        await #expect(throws: DataError.self) { try await repo.add(DiaryLogInput(kind: .note, at: day), userId: testUser) }
    }

    @Test func syncDTORoundTrips() throws {
        let input = DiaryLogInput(kind: .activity, at: day, amount: 220, quantity: 30, label: "Run")
        let model = DiaryLog(userId: testUser, input: input, now: day)
        let copy = DiaryLog(syncDTO: model.makeDTO())
        #expect(copy.id == model.id)
        #expect(copy.input == input)
        #expect(DiaryLog.syncTable.rawValue == "diary_logs")
    }
}

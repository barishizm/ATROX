@testable import DataKit
import Foundation
import SwiftData
import Testing

@Suite struct ProfileRepositoryTests {
    private let clock = TestClock()

    private func makeRepo() throws -> SwiftDataProfileRepository {
        SwiftDataProfileRepository(modelContainer: try DataStore.inMemory(), clock: clock.closure)
    }

    @Test func missingProfileIsNil() async throws {
        #expect(try await makeRepo().profile(userId: testUser) == nil)
    }

    @Test func upsertCreatesPendingRow() async throws {
        let repo = try makeRepo()
        let input = DataFixtures.profileInput(now: clock.now)
        let saved = try await repo.upsert(input, userId: testUser)
        #expect(saved.syncState == .pending)
        #expect(saved.createdAt == clock.now)
        #expect(saved.updatedAt == clock.now)
        #expect(saved.input == input)
        #expect(try await repo.profile(userId: testUser) == saved)
    }

    @Test func secondUpsertUpdatesSameRowAndBumpsUpdatedAt() async throws {
        let repo = try makeRepo()
        let first = try await repo.upsert(DataFixtures.profileInput(now: clock.now), userId: testUser)
        clock.advance(by: 60)
        var changed = first.input
        changed.goal = .fatLoss
        changed.heightCm = 182.5
        let second = try await repo.upsert(changed, userId: testUser)
        #expect(second.id == first.id)
        #expect(second.createdAt == first.createdAt)
        #expect(second.updatedAt == clock.now)
        #expect(second.updatedAt > first.updatedAt)
        #expect(second.input.goal == .fatLoss)
        #expect(second.input.heightCm == 182.5)
    }

    @Test func writeMarksSyncedRowPendingAgain() async throws {
        let container = try DataStore.inMemory()
        let repo = SwiftDataProfileRepository(modelContainer: container, clock: clock.closure)
        let saved = try await repo.upsert(DataFixtures.profileInput(now: clock.now), userId: testUser)
        // Simulate the sync engine confirming the push.
        let context = ModelContext(container)
        let row = try #require(try context.fetch(FetchDescriptor<UserProfile>()).first)
        row.syncState = .synced
        try context.save()
        clock.advance(by: 5)
        var changed = saved.input
        changed.weeklyFrequency = 5
        let updated = try await repo.upsert(changed, userId: testUser)
        #expect(updated.syncState == .pending)
    }

    @Test func profilesAreScopedPerUser() async throws {
        let repo = try makeRepo()
        try await repo.upsert(DataFixtures.profileInput(firstName: "A", now: clock.now), userId: testUser)
        try await repo.upsert(DataFixtures.profileInput(firstName: "B", now: clock.now), userId: otherUser)
        #expect(try await repo.profile(userId: testUser)?.input.firstName == "A")
        #expect(try await repo.profile(userId: otherUser)?.input.firstName == "B")
    }

    @Test func deleteIsSoftAndHidesProfile() async throws {
        let container = try DataStore.inMemory()
        let repo = SwiftDataProfileRepository(modelContainer: container, clock: clock.closure)
        try await repo.upsert(DataFixtures.profileInput(now: clock.now), userId: testUser)
        clock.advance(by: 10)
        try await repo.delete(userId: testUser)
        #expect(try await repo.profile(userId: testUser) == nil)
        let rows = try ModelContext(container).fetch(FetchDescriptor<UserProfile>())
        #expect(rows.count == 1)
        #expect(rows.first?.deletedAt == clock.now)
        #expect(rows.first?.syncState == .pending)
    }

    @Test func upsertAfterDeleteRevivesRow() async throws {
        let repo = try makeRepo()
        let first = try await repo.upsert(DataFixtures.profileInput(now: clock.now), userId: testUser)
        try await repo.delete(userId: testUser)
        let revived = try await repo.upsert(first.input, userId: testUser)
        #expect(revived.id == first.id)
        #expect(revived.deletedAt == nil)
    }

    @Test func deleteWithoutProfileThrowsNotFound() async throws {
        await #expect(throws: DataError.notFound) { try await makeRepo().delete(userId: testUser) }
    }

    @Test func rejectsOutOfRangeValues() async throws {
        let repo = try makeRepo()
        var input = DataFixtures.profileInput(now: clock.now)
        input.heightCm = 99
        await #expect(throws: DataError.invalidValue("heightCm")) { try await repo.upsert(input, userId: testUser) }
        input.heightCm = 180
        input.weeklyFrequency = 8
        await #expect(throws: DataError.invalidValue("weeklyFrequency")) { try await repo.upsert(input, userId: testUser) }
    }
}

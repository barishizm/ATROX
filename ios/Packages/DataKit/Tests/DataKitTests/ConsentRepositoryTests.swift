@testable import DataKit
import Foundation
import Testing

@Suite struct ConsentRepositoryTests {
    private let clock = TestClock()

    private func makeRepo() throws -> SwiftDataConsentRepository {
        SwiftDataConsentRepository(modelContainer: try DataStore.inMemory(), clock: clock.closure)
    }

    @Test func recordStoresPendingRow() async throws {
        let saved = try await makeRepo().record(kind: .terms, version: "2026-11", granted: true, userId: testUser)
        #expect(saved.syncState == .pending)
        #expect(saved.kind == .terms)
        #expect(saved.version == "2026-11")
        #expect(saved.granted)
    }

    @Test func currentIsLatestRowForKind() async throws {
        let repo = try makeRepo()
        try await repo.record(kind: .aiSharing, version: "1", granted: true, userId: testUser)
        clock.advance(by: 60)
        try await repo.record(kind: .aiSharing, version: "1", granted: false, userId: testUser)
        try await repo.record(kind: .terms, version: "1", granted: true, userId: testUser)
        #expect(try await repo.current(kind: .aiSharing, userId: testUser)?.granted == false)
        #expect(try await repo.current(kind: .terms, userId: testUser)?.granted == true)
        #expect(try await repo.current(kind: .mlContribution, userId: testUser) == nil)
        #expect(try await repo.current(kind: .aiSharing, userId: otherUser) == nil)
    }

    @Test func historyKeepsEveryRowOldestFirst() async throws {
        let repo = try makeRepo()
        try await repo.record(kind: .aiSharing, version: "1", granted: true, userId: testUser)
        clock.advance(by: 60)
        try await repo.record(kind: .aiSharing, version: "1", granted: false, userId: testUser)
        let history = try await repo.history(userId: testUser)
        #expect(history.map(\.granted) == [true, false])
    }
}

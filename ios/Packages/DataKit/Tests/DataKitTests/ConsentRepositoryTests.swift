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

@Suite struct ConsentPusherTests {
    private actor RecordingRemote: ConsentRemote {
        var sent: [ConsentSnapshot] = []
        var failAfter: Int?
        func insert(_ consent: ConsentSnapshot) throws {
            if let failAfter, sent.count >= failAfter { throw URLError(.notConnectedToInternet) }
            sent.append(consent)
        }
        func failing(after count: Int) { failAfter = count }
        func stopFailing() { failAfter = nil }
    }

    @Test func grantsAndWithdrawalsAreSentOldestFirstAndMarkedSynced() async throws {
        let clock = TestClock()
        let repo = SwiftDataConsentRepository(modelContainer: try DataStore.inMemory(), clock: clock.closure)
        let remote = RecordingRemote()
        let pusher = ConsentPusher(repository: repo, remote: remote)
        try await repo.record(kind: .aiSharing, version: "1", granted: true, userId: testUser)
        clock.advance(by: 60)
        try await repo.record(kind: .aiSharing, version: "1", granted: false, userId: testUser)
        try await repo.record(kind: .terms, version: "1", granted: true, userId: otherUser)

        #expect(await pusher.push(userId: testUser))
        #expect(await remote.sent.map(\.granted) == [true, false])
        #expect(try await repo.unsynced(userId: testUser).isEmpty)
        #expect(try await repo.unsynced(userId: otherUser).count == 1)
        #expect(await pusher.push(userId: testUser))
        #expect(await remote.sent.count == 2)
    }

    @Test func aFailureStopsTheRunAndTheRestIsRetriedLater() async throws {
        let repo = SwiftDataConsentRepository(modelContainer: try DataStore.inMemory(), clock: TestClock().closure)
        let remote = RecordingRemote()
        let pusher = ConsentPusher(repository: repo, remote: remote)
        try await repo.record(kind: .terms, version: "1", granted: true, userId: testUser)
        try await repo.record(kind: .privacy, version: "1", granted: true, userId: testUser)
        await remote.failing(after: 1)

        #expect(await pusher.push(userId: testUser) == false)
        #expect(try await repo.unsynced(userId: testUser).map(\.kind) == [.privacy])

        await remote.stopFailing()
        #expect(await pusher.push(userId: testUser))
        #expect(await remote.sent.map(\.kind) == [.terms, .privacy])
    }
}

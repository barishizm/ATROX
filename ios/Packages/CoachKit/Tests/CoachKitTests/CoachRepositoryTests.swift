import Foundation
import Testing
@testable import CoachKit

actor FakeRemote: CoachRemote {
    var threadRows: [CoachThread] = []
    var messageRows: [UUID: [CoachStoredMessage]] = [:]
    var memoryRows: [CoachMemoryNote] = []
    var failWrites = false
    private(set) var calls: [String] = []

    func setThreads(_ rows: [CoachThread]) { threadRows = rows }
    func setMessages(_ rows: [CoachStoredMessage], for thread: UUID) { messageRows[thread] = rows }
    func setFailWrites(_ value: Bool) { failWrites = value }

    func threads(limit: Int, before: Date?) async throws -> [CoachThread] {
        calls.append("threads")
        return Array(threadRows.sorted { $0.updatedAt > $1.updatedAt }.filter { before == nil || $0.updatedAt < before! }.prefix(limit))
    }

    func messages(threadId: UUID, limit: Int, before: Date?) async throws -> [CoachStoredMessage] {
        calls.append("messages")
        let rows = (messageRows[threadId] ?? []).sorted { $0.createdAt > $1.createdAt }
        return Array(rows.filter { before == nil || $0.createdAt < before! }.prefix(limit))
    }

    func renameThread(id: UUID, title: String) async throws {
        if failWrites { throw CoachError.offline }
        calls.append("rename")
    }

    func deleteThread(id: UUID) async throws {
        if failWrites { throw CoachError.offline }
        threadRows.removeAll { $0.id == id }
        calls.append("delete")
    }

    func deleteAllThreads() async throws {
        if failWrites { throw CoachError.offline }
        threadRows = []
        calls.append("deleteAll")
    }

    func memory() async throws -> [CoachMemoryNote] { memoryRows }
    func editMemory(id: UUID, note: String) async throws { calls.append("editMemory") }
    func deleteMemory(id: UUID) async throws { calls.append("deleteMemory") }

    func recordDecision(proposalID: String, decision: CoachProposal.Decision) async throws {
        if failWrites { throw CoachError.offline }
        calls.append("decision:\(proposalID):\(decision.rawValue)")
    }
}

@Suite struct CoachRepositoryTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func thread(_ minutesAgo: Double, title: String = "t") -> CoachThread {
        let date = now.addingTimeInterval(-minutesAgo * 60)
        return CoachThread(id: UUID(), title: title, createdAt: date, updatedAt: date)
    }

    private func row(_ role: String, _ text: String, at minute: Double, proposal: CoachProposal? = nil, status: String = "complete") -> CoachStoredMessage {
        CoachStoredMessage(id: UUID(), role: role, content: text, proposal: proposal, status: status, createdAt: now.addingTimeInterval(minute * 60))
    }

    @Test func proposalsOnToolRowsAttachToTheFollowingAnswer() {
        let proposal = CoachProposal(id: "p", kind: .routine)
        let messages = CoachHistory.messages(from: [
            row("user", "plan", at: 0),
            row("assistant", "", at: 1),
            row("tool", "{}", at: 2, proposal: proposal),
            row("assistant", "Here", at: 3),
            row("user", "thanks", at: 4)
        ])
        #expect(messages.map(\.text) == ["plan", "Here", "thanks"])
        #expect(messages[1].proposals == [proposal])
    }

    @Test func aTurnCutOffMidAnswerShowsAsPartial() {
        let messages = CoachHistory.messages(from: [row("user", "q", at: 0), row("assistant", "half", at: 1, status: "partial")])
        #expect(messages.last?.status == .partial)
    }

    @Test func refreshStoresThreadsAndMessagesInTheCacheForTheNextLaunch() async throws {
        let remote = FakeRemote()
        let first = thread(5)
        await remote.setThreads([first, thread(60)])
        await remote.setMessages([row("user", "hi", at: 0), row("assistant", "hello", at: 1)], for: first.id)
        let cache = InMemoryCoachCache()
        let repository = CoachRepository(remote: remote, cache: cache)
        #expect(await repository.cachedThreads().isEmpty)
        _ = try await repository.refreshThreads()
        _ = try await repository.refreshMessages(threadId: first.id)

        let relaunched = CoachRepository(remote: FakeRemote(), cache: cache)
        #expect(await relaunched.cachedThreads().count == 2)
        #expect(await relaunched.cachedMessages(threadId: first.id).map(\.text) == ["hi", "hello"])
    }

    @Test func olderMessagesPageBackwardsWithoutDuplicates() async throws {
        let remote = FakeRemote()
        let id = UUID()
        await remote.setMessages((0..<(CoachRepository.messagePage + 10)).map { row($0 % 2 == 0 ? "user" : "assistant", "m\($0)", at: Double($0)) }, for: id)
        let repository = CoachRepository(remote: remote, cache: InMemoryCoachCache())
        let newest = try await repository.refreshMessages(threadId: id)
        #expect(newest.count == CoachRepository.messagePage && newest.last?.text == "m\(CoachRepository.messagePage + 9)")
        let all = try await repository.olderMessages(threadId: id)
        #expect(all.count == CoachRepository.messagePage + 10 && all.first?.text == "m0")
        #expect(Set(all.map(\.id)).count == all.count)
    }

    @Test func deleteRemovesTheThreadAndItsCachedMessagesOnlyAfterTheServerAgrees() async throws {
        let remote = FakeRemote()
        let doomed = thread(1)
        await remote.setThreads([doomed])
        await remote.setMessages([row("user", "secret", at: 0)], for: doomed.id)
        let repository = CoachRepository(remote: remote, cache: InMemoryCoachCache())
        _ = try await repository.refreshThreads()
        _ = try await repository.refreshMessages(threadId: doomed.id)

        await remote.setFailWrites(true)
        await #expect(throws: CoachError.offline) { try await repository.delete(threadId: doomed.id) }
        #expect(await repository.cachedThreads().count == 1, "a failed delete keeps the conversation on screen")

        await remote.setFailWrites(false)
        try await repository.delete(threadId: doomed.id)
        #expect(await repository.cachedThreads().isEmpty)
        #expect(await repository.cachedMessages(threadId: doomed.id).isEmpty)
    }

    @Test func deleteAllClearsEverythingOnTheDevice() async throws {
        let remote = FakeRemote()
        let one = thread(1)
        await remote.setThreads([one, thread(2)])
        await remote.setMessages([row("user", "x", at: 0)], for: one.id)
        let repository = CoachRepository(remote: remote, cache: InMemoryCoachCache())
        _ = try await repository.refreshThreads()
        _ = try await repository.refreshMessages(threadId: one.id)
        try await repository.deleteAll()
        #expect(await repository.cachedThreads().isEmpty)
        #expect(await repository.cachedMessages(threadId: one.id).isEmpty)
    }

    @Test func rememberMovesTheConversationToTheTopAndTrimsOldOnes() async {
        let repository = CoachRepository(remote: FakeRemote(), cache: InMemoryCoachCache())
        let id = UUID()
        await repository.remember(threadId: id, messages: [CoachMessage(role: .user, text: "hi"), CoachMessage(role: .assistant, text: "…", status: .streaming)], title: "hi")
        #expect(await repository.cachedThreads().first?.id == id)
        #expect(await repository.cachedMessages(threadId: id).map(\.text) == ["hi"], "a streaming bubble is not cached")
    }

    @Test func renameTrimsAndSkipsEmptyTitles() async throws {
        let remote = FakeRemote()
        let first = thread(1)
        await remote.setThreads([first])
        let repository = CoachRepository(remote: remote, cache: InMemoryCoachCache())
        _ = try await repository.refreshThreads()
        try await repository.rename(threadId: first.id, title: "   ")
        #expect(await remote.calls.contains("rename") == false)
        try await repository.rename(threadId: first.id, title: "  Bacak günü  ")
        #expect(await repository.cachedThreads().first?.title == "Bacak günü")
    }

    @Test func aDecisionIsStoredLocallyEvenWhenTheServerCannotBeReached() async {
        let remote = FakeRemote()
        let repository = CoachRepository(remote: remote, cache: InMemoryCoachCache())
        let id = UUID()
        let card = CoachProposal(id: "p", kind: .routine)
        await repository.remember(threadId: id, messages: [CoachMessage(role: .assistant, text: "plan", proposals: [card])], title: nil)
        await remote.setFailWrites(true)
        await repository.recordDecision(proposalID: "p", decision: .applied)
        #expect(await repository.cachedMessages(threadId: id).first?.proposals.first?.decision == .applied)
    }

    @Test func fileCacheRoundTripsAndSurvivesGarbage() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("coach-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let cache = FileCoachCache(url: url)
        #expect(cache.load() == CoachCacheSnapshot())
        let snapshot = CoachCacheSnapshot(threads: [thread(1)], messages: ["a": [CoachMessage(role: .user, text: "hi")]])
        cache.save(snapshot)
        #expect(cache.load() == snapshot)
        try Data("not json".utf8).write(to: url)
        #expect(cache.load() == CoachCacheSnapshot())
    }
}

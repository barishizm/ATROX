import Foundation
import Testing
@testable import CoachKit

@Suite struct SupabaseCoachRemoteTests {
    final class Spy: @unchecked Sendable {
        private let lock = NSLock()
        private(set) var requests: [URLRequest] = []
        var reply = Data("[]".utf8)
        var status = 200

        func record(_ request: URLRequest) -> (Data, URLResponse) {
            lock.withLock { requests.append(request) }
            return (reply, HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
        }
    }

    private func remote(_ spy: Spy, token: String? = "tok") -> SupabaseCoachRemote {
        SupabaseCoachRemote(baseURL: URL(string: "https://example.test")!, anonKey: "anon", accessToken: { token }) { spy.record($0) }
    }

    @Test func threadsQueryIsPagedNewestFirstAndSkipsDeleted() async throws {
        let spy = Spy()
        spy.reply = Data(#"[{"id":"11111111-1111-4111-8111-111111111111","title":"Plan","created_at":"2026-11-14T10:00:00.123456+00:00","updated_at":"2026-11-14T11:00:00+00:00"}]"#.utf8)
        let threads = try await remote(spy).threads(limit: 30, before: nil)
        #expect(threads.count == 1 && threads[0].title == "Plan")
        let url = try #require(spy.requests.first?.url?.absoluteString)
        #expect(url.contains("coach_threads") && url.contains("order=updated_at.desc") && url.contains("deleted_at=is.null") && url.contains("limit=30"))
        #expect(spy.requests.first?.value(forHTTPHeaderField: "Authorization") == "Bearer tok")
    }

    @Test func messagesParseProposalsOnToolRows() async throws {
        let spy = Spy()
        spy.reply = Data(#"[{"id":"22222222-2222-4222-8222-222222222222","role":"tool","content":"{}","status":"complete","created_at":"2026-11-14T10:00:00+00:00","proposal":{"id":"p","kind":"exercise_swap","data":{},"decision":"applied"}}]"#.utf8)
        let rows = try await remote(spy).messages(threadId: UUID(), limit: 10, before: Date())
        #expect(rows.first?.proposal?.kind == .exerciseSwap && rows.first?.proposal?.decision == .applied)
        #expect(spy.requests.first?.url?.absoluteString.contains("created_at=lt.") == true)
    }

    @Test func deletesGoThroughTheRpcFunctions() async throws {
        let spy = Spy()
        let id = UUID()
        try await remote(spy).deleteThread(id: id)
        try await remote(spy).deleteAllThreads()
        try await remote(spy).deleteMemory(id: id)
        let paths = spy.requests.compactMap { $0.url?.path }
        #expect(paths == ["/rest/v1/rpc/coach_delete_thread", "/rest/v1/rpc/coach_delete_all_threads", "/rest/v1/rpc/coach_delete_memory"])
        #expect(spy.requests.allSatisfy { $0.httpMethod == "POST" })
    }

    @Test func httpFailuresAndMissingSessionsAreTyped() async {
        let spy = Spy()
        spy.status = 401
        await #expect(throws: CoachError.unauthorized) { try await remote(spy).deleteAllThreads() }
        await #expect(throws: CoachError.unauthorized) { try await remote(Spy(), token: nil).memory() }
    }
}

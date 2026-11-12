@testable import DataKit
import Foundation
import Testing

/// Records requests and answers with canned responses.
final class StubHTTP: @unchecked Sendable {
    private let lock = NSLock()
    private var log: [URLRequest] = []
    struct Answer {
        let status: Int
        let body: Data
        let headers: [String: String]
    }

    private var answers: [Answer]

    /// `(status, body)` pairs, optionally with headers.
    init(_ answers: [(Int, String)], headers: [Int: [String: String]] = [:]) {
        self.answers = answers.enumerated().map { index, answer in
            Answer(status: answer.0, body: Data(answer.1.utf8), headers: headers[index] ?? [:])
        }
    }

    var requests: [URLRequest] { lock.withLock { log } }

    var fetch: SupabaseRemoteStore.Fetch {
        { [self] request in
            let answer = lock.withLock {
                log.append(request)
                return answers.isEmpty ? Answer(status: 500, body: Data(), headers: [:]) : answers.removeFirst()
            }
            let response = HTTPURLResponse(url: request.url!, statusCode: answer.status, httpVersion: nil, headerFields: answer.headers)!
            return (answer.body, response)
        }
    }
}

@Suite("SupabaseRemoteStore (P044)")
struct SupabaseRemoteStoreTests {
    private func store(_ stub: StubHTTP, token: String? = "jwt") -> SupabaseRemoteStore {
        SupabaseRemoteStore(baseURL: URL(string: "http://127.0.0.1:54321")!, anonKey: "anon", accessToken: { token }, fetch: stub.fetch)
    }

    @Test func upsertPostsAllRowsWithMergeAndReturnsTheStoredOnes() async throws {
        let stub = StubHTTP([(201, #"[{"id":"\#(testUser.uuidString)","updated_at":"2026-11-13T10:00:00.5+00:00"}]"#)])
        let rows = try await store(stub).upsert(table: .bodyMeasurements, rows: [["id": .string(testUser.uuidString)]])

        let request = try #require(stub.requests.first)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.absoluteString == "http://127.0.0.1:54321/rest/v1/body_measurements?on_conflict=id")
        #expect(request.value(forHTTPHeaderField: "Prefer") == "resolution=merge-duplicates,return=representation")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer jwt")
        #expect(request.value(forHTTPHeaderField: "apikey") == "anon")
        #expect(rows.first?.rowUpdatedAt == "2026-11-13T10:00:00.5+00:00")
    }

    @Test func changesUseAKeysetFilterAfterTheCursor() async throws {
        let stub = StubHTTP([(200, "[]")])
        let cursor = SyncCursor(updatedAt: "2026-11-13T10:00:00.123456+00:00", id: testUser)
        _ = try await store(stub).changes(table: .sets, after: cursor, limit: 500)

        let url = try #require(stub.requests.first?.url?.absoluteString)
        #expect(url.hasPrefix("http://127.0.0.1:54321/rest/v1/sets?select=*&or="))
        #expect(url.hasSuffix("&order=updated_at.asc,id.asc&limit=500"))
        let decoded = try #require(url.removingPercentEncoding)
        let stamp = "\"2026-11-13T10:00:00.123456+00:00\""
        #expect(decoded.contains("or=(updated_at.gt.\(stamp),and(updated_at.eq.\(stamp),id.gt.11111111-1111-4111-8111-111111111111))"))
        #expect(!url.contains("+"))
    }

    @Test func countReadsTheContentRangeTotal() async throws {
        let stub = StubHTTP([(206, "[]"), (200, "[]")], headers: [0: ["Content-Range": "0-0/123"], 1: ["Content-Range": "*/0"]])
        let remote = store(stub)
        #expect(try await remote.countChanges(table: .workouts, after: nil) == 123)
        #expect(try await remote.countChanges(table: .workouts, after: nil) == 0)
        #expect(stub.requests.first?.value(forHTTPHeaderField: "Prefer") == "count=exact")
    }

    @Test func serverTimeCallsTheRpc() async throws {
        let stub = StubHTTP([(200, #""2026-11-13T10:00:00.25+00:00""#)])
        let time = try await store(stub).serverTime()
        #expect(stub.requests.first?.url?.path == "/rest/v1/rpc/server_time")
        #expect(SyncTime.timestamp(time) == "2026-11-13T10:00:00.250000Z")
    }

    @Test func errorsAreSortedIntoRetryOrGiveUp() {
        func map(_ status: Int, _ body: String) -> RemoteStoreError { SupabaseRemoteStore.error(status: status, body: Data(body.utf8)) }
        #expect(map(400, #"{"code":"23514","message":"violates check constraint"}"#) == .permanent("23514 violates check constraint"))
        #expect(map(403, #"{"code":"42501","message":"row-level security"}"#) == .permanent("42501 row-level security"))
        #expect(map(401, #"{"code":"PGRST301","message":"JWT expired"}"#) == .unauthorized)
        #expect(map(503, "") == .transient(" HTTP 503"))
        #expect(map(429, "") == .transient(" HTTP 429"))
    }

    @Test func noSessionMeansUnauthorizedWithoutARequest() async throws {
        let stub = StubHTTP([])
        await #expect(throws: RemoteStoreError.unauthorized) { try await store(stub, token: nil).serverTime() }
        #expect(stub.requests.isEmpty)
    }
}

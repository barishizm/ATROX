import Foundation
import Testing
@testable import CoachKit

@Suite struct CoachChatServiceTests {
    private let request = CoachChatRequest(
        threadId: nil, clientMessageId: UUID(), message: "3 günlük program yap", locale: "tr", timeZone: "Europe/Istanbul"
    )

    private func service(_ transport: FakeTransport, refreshed: String? = "fresh", idle: Duration = .seconds(30)) -> SupabaseCoachChatService {
        SupabaseCoachChatService(
            baseURL: URL(string: "https://example.test")!, anonKey: "anon", accessToken: { "old" }, refreshedToken: { refreshed },
            client: SSEClient(transport: transport, idleTimeout: idle)
        )
    }

    private func collect(_ stream: AsyncThrowingStream<CoachEvent, any Error>) async throws -> [CoachEvent] {
        var events: [CoachEvent] = []
        for try await event in stream { events.append(event) }
        return events
    }

    @Test func streamsARecordedTurnInOrderAcrossTinyChunks() async throws {
        let transport = FakeTransport([FakeTransport.ok(Dump.turn, chunk: 5)])
        let events = try await collect(service(transport).stream(request))
        #expect(events.count == 8)
        #expect(events.last == .done(threadId: UUID(uuidString: Dump.thread)!))
        let sent = try #require(transport.requests.first)
        #expect(sent.url?.path == "/functions/v1/coach-chat" && sent.value(forHTTPHeaderField: "Authorization") == "Bearer old")
        let body = try #require(try JSONSerialization.jsonObject(with: sent.httpBody ?? Data()) as? [String: String])
        #expect(body["client_message_id"] == request.clientMessageId.uuidString.lowercased() && body["time_zone"] == "Europe/Istanbul")
        #expect(body["thread_id"] == nil)
    }

    @Test func anExpiredTokenIsRefreshedOnceAndTheRequestRepeated() async throws {
        let transport = FakeTransport([FakeTransport.error(401, code: "unauthorized"), FakeTransport.ok(Dump.turn)])
        let events = try await collect(service(transport).stream(request))
        #expect(events.count == 8)
        #expect(transport.requests.map { $0.value(forHTTPHeaderField: "Authorization") } == ["Bearer old", "Bearer fresh"])
    }

    @Test func aSecondUnauthorizedGivesUp() async {
        let transport = FakeTransport([FakeTransport.error(401, code: "unauthorized"), FakeTransport.error(401, code: "unauthorized")])
        await #expect(throws: CoachError.unauthorized) { try await collect(service(transport).stream(request)) }
        #expect(transport.requests.count == 2)
    }

    @Test func noTokenMeansUnauthorizedWithoutAnyRequest() async {
        let transport = FakeTransport([])
        let service = SupabaseCoachChatService(
            baseURL: URL(string: "https://example.test")!, anonKey: "anon", accessToken: { nil }, refreshedToken: { nil },
            client: SSEClient(transport: transport)
        )
        await #expect(throws: CoachError.unauthorized) { try await collect(service.stream(request)) }
        #expect(transport.requests.isEmpty)
    }

    @Test func httpErrorsBecomeTypedErrors() async {
        let cases: [(FakeTransport.Reply, CoachError)] = [
            (FakeTransport.error(403, code: "consent_required", details: #"{"required_version":"2026-11"}"#), .consentRequired(requiredVersion: "2026-11")),
            (FakeTransport.error(400, code: "duplicate_message"), .duplicateMessage),
            (FakeTransport.error(503, code: "coach_unavailable"), .unavailable)
        ]
        for (reply, expected) in cases {
            await #expect(throws: expected) { try await collect(service(FakeTransport([reply])).stream(request)) }
        }
    }

    @Test func aDroppedConnectionIsReportedAsOffline() async {
        let reply = FakeTransport.Reply(chunks: [Data("event: text_delta\ndata: {\"text\":\"a\"}\n\n".utf8)], failure: URLError(.networkConnectionLost))
        await #expect(throws: CoachError.offline) { try await collect(service(FakeTransport([reply])).stream(request)) }
    }

    @Test func aStalledStreamTimesOut() async {
        let reply = FakeTransport.Reply(chunks: [Data("event: text_delta\ndata: {\"text\":\"a\"}\n\n".utf8)], hang: true)
        await #expect(throws: CoachError.timeout) {
            try await collect(service(FakeTransport([reply]), idle: .milliseconds(600)).stream(request))
        }
    }

    @Test func cancellingTheConsumerStopsTheStream() async {
        let reply = FakeTransport.Reply(hang: true)
        let stream = service(FakeTransport([reply])).stream(request)
        let task = Task { try await collect(stream) }
        try? await Task.sleep(for: .milliseconds(100))
        task.cancel()
        let result = await task.result
        if case .success(let events) = result { #expect(events.isEmpty) }
    }
}

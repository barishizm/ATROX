import Foundation
import Testing
@testable import CoachKit

@Suite struct ConsentGatedChatServiceTests {
    private let request = CoachChatRequest(threadId: nil, clientMessageId: UUID(), message: "hi", locale: "en", timeZone: "UTC")

    private final class Counting: CoachChatService, @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        var calls: Int { lock.withLock { count } }
        func stream(_ request: CoachChatRequest) -> AsyncThrowingStream<CoachEvent, any Error> {
            lock.withLock { count += 1 }
            return AsyncThrowingStream { $0.finish() }
        }
    }

    private final class Flag: @unchecked Sendable {
        private let lock = NSLock()
        private var value: Bool
        init(_ value: Bool) { self.value = value }
        var current: Bool {
            get { lock.withLock { value } }
            set { lock.withLock { value = newValue } }
        }
    }

    private func drain(_ stream: AsyncThrowingStream<CoachEvent, any Error>) async throws {
        for try await _ in stream {}
    }

    @Test func withoutConsentTheEndpointIsNeverCalled() async {
        let inner = Counting()
        let gated = ConsentGatedChatService(inner, requiredVersion: "2026-11") { false }
        await #expect(throws: CoachError.consentRequired(requiredVersion: "2026-11")) { try await drain(gated.stream(request)) }
        #expect(inner.calls == 0)
    }

    @Test func withConsentTheTurnGoesThrough() async throws {
        let inner = Counting()
        try await drain(ConsentGatedChatService(inner) { true }.stream(request))
        #expect(inner.calls == 1)
    }

    @Test func withdrawingStopsTheNextTurn() async throws {
        let inner = Counting()
        let flag = Flag(true)
        let gated = ConsentGatedChatService(inner) { flag.current }
        try await drain(gated.stream(request))
        flag.current = false
        await #expect(throws: CoachError.self) { try await drain(gated.stream(request)) }
        #expect(inner.calls == 1)
    }
}

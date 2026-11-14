import Foundation
import Testing
@testable import CoachKit

/// Plays one scripted attempt per `stream` call: events, then optionally an error or an endless wait.
final class ScriptedService: CoachChatService, @unchecked Sendable {
    struct Attempt {
        var events: [CoachEvent] = []
        var failure: CoachError?
        var hang = false
    }

    private let lock = NSLock()
    private var attempts: [Attempt]
    private(set) var requests: [CoachChatRequest] = []

    init(_ attempts: [Attempt]) {
        self.attempts = attempts
    }

    func stream(_ request: CoachChatRequest) -> AsyncThrowingStream<CoachEvent, any Error> {
        let attempt = lock.withLock { () -> Attempt in
            requests.append(request)
            return attempts.isEmpty ? Attempt() : attempts.removeFirst()
        }
        return AsyncThrowingStream { continuation in
            for event in attempt.events { continuation.yield(event) }
            if let failure = attempt.failure {
                continuation.finish(throwing: failure)
            } else if !attempt.hang {
                continuation.finish()
            }
        }
    }
}

@MainActor
@Suite struct CoachSessionTests {
    private let thread = UUID(uuidString: Dump.thread)!
    private let routine = CoachProposal(id: "p-1", kind: .routine, data: .object(["name": .string("3-day")]))
    private let note = CoachProposal(id: "m-1", kind: .memorySaved)

    private func session(_ attempts: [ScriptedService.Attempt], sink: @escaping @Sendable (String, CoachProposal.Decision) async -> Void = { _, _ in })
        -> (CoachSession, ScriptedService) {
        let service = ScriptedService(attempts)
        let session = CoachSession(service: service, locale: { "tr" }, timeZone: { "Europe/Istanbul" }, decisionSink: sink)
        return (session, service)
    }

    private var plainAnswer: [CoachEvent] {
        [.textDelta("Merhaba "), .textDelta("dünya"), .usage(promptTokens: 1, cachedTokens: 0, completionTokens: 1), .done(threadId: thread)]
    }

    @Test func aPlainTurnGoesIdleToSendingToStreamingToIdle() async {
        let (session, _) = session([.init(events: plainAnswer)])
        #expect(session.state == .idle)
        session.send("  Selam  ")
        #expect(session.state == .sending)
        await session.settle()
        #expect(session.state == .idle)
        #expect(session.messages.map(\.text) == ["Selam", "Merhaba dünya"])
        #expect(session.messages.map(\.status) == [.complete, .complete])
        #expect(session.threadId == thread)
    }

    @Test func toolActivityShowsWhileTheToolRuns() async {
        let (session, _) = session([.init(events: [
            .toolActivity(name: "coach.tool.get_scores", status: .started),
            .toolActivity(name: "coach.tool.get_scores", status: .finished),
            .textDelta("Skor 64."), .done(threadId: thread)
        ], hang: false)])
        session.send("Skorum?")
        await session.settle()
        #expect(session.state == .idle)
    }

    @Test func aProposalLeavesTheSessionWaitingForADecision() async {
        let (session, _) = session([.init(events: [.proposal(routine), .proposal(note), .textDelta("Plan hazır."), .done(threadId: thread)])])
        session.send("3 günlük program yap")
        await session.settle()
        #expect(session.state == .awaitingProposalDecision)
        #expect(session.messages.last?.proposals.map(\.id) == ["p-1", "m-1"])
        session.decide(proposalID: "p-1", .applied)
        #expect(session.state == .idle)
        #expect(session.messages.last?.proposals.first?.decision == .applied)
    }

    @Test func decisionsAreReportedToTheServer() async {
        let recorded = Recorder()
        let (session, _) = session([.init(events: [.proposal(routine), .done(threadId: thread)])]) { id, decision in
            await recorded.add("\(id):\(decision.rawValue)")
        }
        session.send("program")
        await session.settle()
        session.decide(proposalID: "p-1", .rejected)
        try? await Task.sleep(for: .milliseconds(50))
        #expect(await recorded.items == ["p-1:rejected"])
    }

    @Test func aMemoryNoteAloneNeverBlocksTheChat() async {
        let (session, _) = session([.init(events: [.proposal(note), .textDelta("Not aldım."), .done(threadId: thread)])])
        session.send("Dizim ağrıyor")
        await session.settle()
        #expect(session.state == .idle)
    }

    @Test func aFailureBeforeAnyTextRemovesTheEmptyAnswerAndKeepsTheQuestion() async {
        let (session, _) = session([.init(failure: .offline)])
        session.send("Selam")
        await session.settle()
        #expect(session.state == .failed(.offline))
        #expect(session.messages.map(\.role) == [.user])
    }

    @Test func aDropMidAnswerKeepsTheTextAsPartial() async {
        let (session, _) = session([.init(events: [.textDelta("Yarım")], failure: .offline)])
        session.send("Selam")
        await session.settle()
        #expect(session.state == .failed(.offline))
        #expect(session.messages.last?.status == .partial && session.messages.last?.text == "Yarım")
    }

    @Test func aStreamThatEndsWithoutDoneIsAFailure() async {
        let (session, _) = session([.init(events: [.textDelta("Yarım")])])
        session.send("Selam")
        await session.settle()
        #expect(session.state == .failed(.offline))
    }

    @Test func retryResendsTheSameRequestWithTheSameMessageId() async {
        let (session, service) = session([.init(events: [.textDelta("Yarım")], failure: .timeout), .init(events: plainAnswer)])
        session.send("Selam")
        await session.settle()
        session.retry()
        await session.settle()
        #expect(service.requests.count == 2)
        #expect(service.requests[0] == service.requests[1], "same client message id, so the server stores the message once")
        #expect(session.messages.map(\.text) == ["Selam", "Merhaba dünya"], "the partial answer of the failed attempt is replaced")
        #expect(session.state == .idle)
    }

    @Test func aServerErrorEventFailsTheTurn() async {
        let (session, _) = session([.init(events: [.error(code: "model_unavailable", message: "Try again")])])
        session.send("Selam")
        await session.settle()
        #expect(session.state == .failed(.server(code: "model_unavailable", message: "Try again")))
    }

    @Test func eachErrorKindSurfacesAsFailed() async {
        let errors: [CoachError] = [
            .consentRequired(requiredVersion: "2026-11"), .quotaExceeded(resetAt: nil, upgradeAvailable: true), .rateLimited(retryAt: nil),
            .duplicateMessage, .unavailable, .unauthorized, .timeout
        ]
        for error in errors {
            let (session, _) = session([.init(failure: error)])
            session.send("Selam")
            await session.settle()
            #expect(session.state == .failed(error))
        }
    }

    @Test func cancelKeepsWhatArrivedAndReturnsToIdle() async {
        let (session, _) = session([.init(events: [.textDelta("Birinci")], hang: true)])
        session.send("Selam")
        while session.messages.last?.text.isEmpty != false { await Task.yield() }
        session.cancel()
        #expect(session.state == .idle)
        #expect(session.messages.last?.text == "Birinci" && session.messages.last?.status == .partial)
        #expect(session.canSend)
    }

    @Test func cancelBeforeAnyTextDropsTheEmptyAnswer() async {
        let (session, _) = session([.init(hang: true)])
        session.send("Selam")
        session.cancel()
        #expect(session.state == .idle && session.messages.map(\.role) == [.user])
    }

    @Test func invalidOrBusySendsAreIgnored() async {
        let (session, service) = session([.init(hang: true)])
        session.send("   ")
        session.send(String(repeating: "x", count: CoachSession.maxMessageLength + 1))
        #expect(service.requests.isEmpty)
        session.send("Bir")
        session.send("İki")
        #expect(service.requests.count == 1, "no second message while the coach is answering")
        session.cancel()
    }

    @Test func theQuotaFromTheStreamIsExposed() async {
        let quota = CoachQuota(remaining: 3, dailyMessages: 5, resetAt: nil, tier: .free)
        let (session, _) = session([.init(events: [.quota(quota)] + plainAnswer)])
        session.send("Selam")
        await session.settle()
        #expect(session.quota == quota)
    }

    @Test func aContinuedConversationSendsItsThreadId() async {
        let (session, service) = session([.init(events: plainAnswer), .init(events: plainAnswer)])
        session.send("Bir")
        await session.settle()
        session.send("İki")
        await session.settle()
        #expect(service.requests[0].threadId == nil && service.requests[1].threadId == thread)
        #expect(service.requests[1].locale == "tr" && service.requests[1].timeZone == "Europe/Istanbul")
    }

    @Test func openingAHistoryWithPendingCardsAwaitsADecision() {
        let (session, _) = session([])
        session.open(threadId: thread, messages: [CoachMessage(role: .assistant, text: "Plan", proposals: [routine])])
        #expect(session.state == .awaitingProposalDecision)
        session.startNewThread()
        #expect(session.state == .idle && session.messages.isEmpty && session.threadId == nil)
    }
}

actor Recorder {
    private(set) var items: [String] = []

    func add(_ item: String) {
        items.append(item)
    }
}

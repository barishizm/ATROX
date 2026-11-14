import Foundation
import Observation

/// The state machine of one open conversation (P079):
///
///     idle ─send→ sending ─first event→ streaming(toolActivity?) ─done→ idle | awaitingProposalDecision
///                    └──────────── any error ───────────────────────────→ failed(error) ─retry→ sending
///
/// Text deltas pile up in the last assistant message. `cancel()` keeps what has arrived (marked partial). `retry()`
/// re-sends the same request with the same client message id, so the server does not store the message twice.
@MainActor
@Observable
public final class CoachSession {
    public enum State: Sendable, Equatable {
        case idle
        case sending
        /// `toolActivity` is the localisation key of what the coach is looking at right now (`coach.tool.<name>`).
        case streaming(toolActivity: String?)
        /// The answer is complete, but proposal cards still wait for Apply / Edit / Reject.
        case awaitingProposalDecision
        case failed(CoachError)
    }

    public static let maxMessageLength = 2000

    public private(set) var state: State = .idle
    public private(set) var messages: [CoachMessage] = []
    public private(set) var threadId: UUID?
    public private(set) var quota: CoachQuota?

    @ObservationIgnored private let service: any CoachChatService
    @ObservationIgnored private let locale: @Sendable () -> String
    @ObservationIgnored private let timeZone: @Sendable () -> String
    @ObservationIgnored private let makeID: @Sendable () -> UUID
    @ObservationIgnored private let decisionSink: @Sendable (_ proposalID: String, _ decision: CoachProposal.Decision) async -> Void
    @ObservationIgnored private var lastRequest: CoachChatRequest?
    @ObservationIgnored private var task: Task<Void, Never>?

    public init(
        service: any CoachChatService,
        locale: @escaping @Sendable () -> String = { Locale.current.language.languageCode?.identifier ?? "en" },
        timeZone: @escaping @Sendable () -> String = { TimeZone.current.identifier },
        makeID: @escaping @Sendable () -> UUID = { UUID() },
        decisionSink: @escaping @Sendable (String, CoachProposal.Decision) async -> Void = { _, _ in }
    ) {
        self.service = service
        self.locale = locale
        self.timeZone = timeZone
        self.makeID = makeID
        self.decisionSink = decisionSink
    }

    public var isBusy: Bool {
        switch state {
        case .sending, .streaming: true
        case .idle, .awaitingProposalDecision, .failed: false
        }
    }

    public var canSend: Bool { !isBusy }

    /// Shows an existing conversation (loaded from the repository) and continues it with the next message.
    public func open(threadId: UUID?, messages: [CoachMessage]) {
        cancel()
        self.threadId = threadId
        self.messages = messages
        lastRequest = nil
        state = pendingProposalExists ? .awaitingProposalDecision : .idle
    }

    public func startNewThread() {
        open(threadId: nil, messages: [])
    }

    /// Text that may be sent: trimmed, not empty, within the server's limit.
    public static func sendable(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || trimmed.count > maxMessageLength ? nil : trimmed
    }

    public func send(_ text: String) {
        guard canSend, let message = Self.sendable(text) else { return }
        let request = CoachChatRequest(threadId: threadId, clientMessageId: makeID(), message: message, locale: locale(), timeZone: timeZone())
        messages.append(CoachMessage(id: request.clientMessageId, role: .user, text: message))
        start(request)
    }

    /// After a failure: the same request again. The unfinished answer of the failed attempt is dropped first.
    public func retry() {
        guard case .failed = state, let request = lastRequest else { return }
        if let last = messages.last, last.role == .assistant, last.status != .complete { messages.removeLast() }
        start(request)
    }

    /// Stops the answer. Text that already arrived stays (the server stores the partial turn too).
    public func cancel() {
        guard isBusy else { return }
        task?.cancel()
        task = nil
        finishAssistant(as: .partial)
        state = pendingProposalExists ? .awaitingProposalDecision : .idle
    }

    /// Waits for the running turn (tests, and callers that must not move on before it ends).
    public func settle() async {
        await task?.value
    }

    public func decide(proposalID: String, _ decision: CoachProposal.Decision) {
        for index in messages.indices {
            guard let position = messages[index].proposals.firstIndex(where: { $0.id == proposalID }) else { continue }
            messages[index].proposals[position].decision = decision
        }
        if state == .awaitingProposalDecision, !pendingProposalExists { state = .idle }
        let sink = decisionSink
        Task { await sink(proposalID, decision) }
    }

    private var pendingProposalExists: Bool {
        messages.contains { $0.proposals.contains(where: \.needsDecision) }
    }

    private func start(_ request: CoachChatRequest) {
        lastRequest = request
        messages.append(CoachMessage(id: makeID(), role: .assistant, text: "", status: .streaming))
        state = .sending
        let stream = service.stream(request)
        task = Task { [weak self] in
            do {
                for try await event in stream {
                    guard let self else { return }
                    self.handle(event)
                }
                self?.streamEnded()
            } catch {
                self?.fail(CoachError.from(error))
            }
        }
    }

    private func handle(_ event: CoachEvent) {
        if case .sending = state { state = .streaming(toolActivity: nil) }
        switch event {
        case .textDelta(let text):
            mutateAssistant { $0.text += text }
        case .toolActivity(let name, let status):
            state = .streaming(toolActivity: status == .started ? name : nil)
        case .proposal(let proposal):
            mutateAssistant { $0.proposals.append(proposal) }
        case .quota(let value):
            quota = value
        case .usage:
            break
        case .error(let code, let message):
            fail(.server(code: code, message: message))
        case .done(let id):
            threadId = id
            finishAssistant(as: .complete)
            state = pendingProposalExists ? .awaitingProposalDecision : .idle
            task = nil
        }
    }

    /// The stream ended without a `done` event: the connection dropped.
    private func streamEnded() {
        guard isBusy else { return }
        fail(.offline)
    }

    private func fail(_ error: CoachError) {
        guard isBusy else { return }
        task?.cancel()
        task = nil
        if error == .cancelled {
            cancel()
            return
        }
        if let last = messages.last, last.role == .assistant, last.text.isEmpty, last.proposals.isEmpty {
            messages.removeLast()
        } else {
            finishAssistant(as: .partial)
        }
        state = .failed(error)
    }

    private func mutateAssistant(_ change: (inout CoachMessage) -> Void) {
        guard let index = messages.indices.last, messages[index].role == .assistant else { return }
        change(&messages[index])
    }

    private func finishAssistant(as status: CoachMessage.Status) {
        guard let index = messages.indices.last, messages[index].role == .assistant, messages[index].status == .streaming else { return }
        if messages[index].text.isEmpty, messages[index].proposals.isEmpty {
            messages.remove(at: index)
        } else {
            messages[index].status = status
        }
    }
}

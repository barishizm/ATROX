import CoachKit
import DataKit
import Foundation
import Observation

/// What the coach tab needs from the app, built once by the container.
struct CoachDependencies: Sendable {
    let chat: any CoachChatService
    let repository: CoachRepository
    /// Proactive comments (P083); nil when the server is not configured.
    let digest: (any CoachDigestService)?

    init(chat: any CoachChatService, repository: CoachRepository, digest: (any CoachDigestService)? = nil) {
        self.chat = chat
        self.repository = repository
        self.digest = digest
    }
}

/// The coach tab (P080): one open conversation, the list of conversations, proposal decisions and the starter questions.
@MainActor
@Observable
final class CoachModel {
    enum Banner: Equatable {
        /// A proposal was applied; `routineId` lets the user jump to it.
        case applied(routineId: UUID?)
        case applyFailed
        case memoryRemoved
    }

    let session: CoachSession
    private(set) var threads: [CoachThread] = []
    private(set) var suggestions: [String] = []
    private(set) var isOnline = true
    private(set) var isLoadingThreads = false
    var draft = ""
    var banner: Banner?

    @ObservationIgnored private let repository: CoachRepository
    @ObservationIgnored private let applier: ProposalApplier?
    @ObservationIgnored private let facts: @MainActor () async -> CoachSuggestions.Facts
    @ObservationIgnored private let locale: Locale
    @ObservationIgnored private var monitor: Task<Void, Never>?

    init(
        session: CoachSession, repository: CoachRepository, applier: ProposalApplier?, locale: Locale,
        facts: @escaping @MainActor () async -> CoachSuggestions.Facts
    ) {
        self.session = session
        self.repository = repository
        self.applier = applier
        self.locale = locale
        self.facts = facts
    }

    /// First appearance: what is cached shows at once, then the server catches up.
    func start() async {
        suggestions = CoachSuggestions.make(await facts(), locale: locale)
        threads = await repository.cachedThreads()
        if session.messages.isEmpty, session.threadId == nil, let latest = threads.first {
            session.open(threadId: latest.id, messages: await repository.cachedMessages(threadId: latest.id))
        }
        await refresh()
    }

    func refresh() async {
        isLoadingThreads = true
        defer { isLoadingThreads = false }
        guard let fresh = try? await repository.refreshThreads() else { return }
        threads = fresh
        if !session.isBusy, let id = session.threadId, let messages = try? await repository.refreshMessages(threadId: id) {
            session.open(threadId: id, messages: messages)
        } else if session.messages.isEmpty, session.threadId == nil, let latest = fresh.first,
                  let messages = try? await repository.refreshMessages(threadId: latest.id) {
            session.open(threadId: latest.id, messages: messages)
        }
    }

    /// Tracks the connection so an offline coach shows a clear state instead of a failing send.
    func watchConnectivity() async {
        for await online in NetworkPathMonitor.updates() { isOnline = online }
    }

    // MARK: Sending

    var canSend: Bool { isOnline && session.canSend && CoachSession.sendable(draft) != nil }
    var characterCount: Int { draft.trimmingCharacters(in: .whitespacesAndNewlines).count }
    var isOverLimit: Bool { characterCount > CoachSession.maxMessageLength }

    /// The quota is used up: the composer is replaced by the reset time (and the Pro call for free users).
    var quotaExhausted: Bool {
        if case .failed(.quotaExceeded) = session.state { return true }
        return session.quota.map { $0.remaining <= 0 } ?? false
    }

    func send() {
        guard canSend, let text = CoachSession.sendable(draft) else { return }
        draft = ""
        deliver(text)
    }

    /// A starter question or "ask the coach" text goes out as it is.
    func ask(_ text: String) {
        guard isOnline, session.canSend, let clean = CoachSession.sendable(text) else { return }
        deliver(clean)
    }

    func stop() {
        session.cancel()
        remember()
    }

    func retry() {
        session.retry()
        Task { [weak self] in
            await self?.session.settle()
            self?.remember()
        }
    }

    private func deliver(_ text: String) {
        banner = nil
        session.send(text)
        Task { [weak self] in
            await self?.session.settle()
            self?.remember()
        }
    }

    /// The conversation is cached right after each turn, so closing the app never loses what was on screen.
    private func remember() {
        guard let id = session.threadId else { return }
        let messages = session.messages
        let title = messages.first { $0.role == .user }.map { String($0.text.prefix(60)) }
        Task { [weak self] in
            guard let self else { return }
            await repository.remember(threadId: id, messages: messages, title: title)
            threads = await repository.cachedThreads()
        }
    }

    // MARK: Proposals

    func apply(_ proposal: CoachProposal, thenEdit: Bool = false) async {
        guard let applier else {
            banner = .applyFailed
            return
        }
        do {
            let outcome = try await applier.apply(proposal)
            decide(proposal, thenEdit ? .edited : .applied)
            switch outcome {
            case .routineCreated(let id, _), .routineChanged(let id, _): banner = .applied(routineId: id)
            case .goalUpdated, .nothingToChange: banner = .applied(routineId: nil)
            }
        } catch {
            banner = .applyFailed
        }
    }

    func reject(_ proposal: CoachProposal) {
        decide(proposal, .rejected)
    }

    /// "Geri al" on the memory notice: the note is deleted for good.
    func undoMemory(_ proposal: CoachProposal) async {
        guard let id = proposal.data["memory_id"]?.string.flatMap(UUID.init(uuidString:)) else { return }
        do {
            try await repository.deleteMemory(id: id)
            decide(proposal, .undone)
            banner = .memoryRemoved
        } catch {
            banner = .applyFailed
        }
    }

    private func decide(_ proposal: CoachProposal, _ decision: CoachProposal.Decision) {
        session.decide(proposalID: proposal.id, decision)
        remember()
    }

    // MARK: Conversations

    func newConversation() {
        session.startNewThread()
        banner = nil
    }

    func open(_ thread: CoachThread) async {
        let cached = await repository.cachedMessages(threadId: thread.id)
        session.open(threadId: thread.id, messages: cached)
        if let fresh = try? await repository.refreshMessages(threadId: thread.id), !session.isBusy, session.threadId == thread.id {
            session.open(threadId: thread.id, messages: fresh)
        }
    }

    func rename(_ thread: CoachThread, to title: String) async {
        try? await repository.rename(threadId: thread.id, title: title)
        threads = await repository.cachedThreads()
    }

    func delete(_ thread: CoachThread) async {
        guard (try? await repository.delete(threadId: thread.id)) != nil else { return }
        threads = await repository.cachedThreads()
        if session.threadId == thread.id { session.startNewThread() }
    }

    func deleteAll() async {
        guard (try? await repository.deleteAll()) != nil else { return }
        threads = []
        session.startNewThread()
    }
}

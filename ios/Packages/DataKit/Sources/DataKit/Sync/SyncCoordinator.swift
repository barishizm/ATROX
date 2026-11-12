import Foundation
import Observation
import SwiftData

/// Why a sync was asked for (logged; `localChange` skips the pass when nothing is pending).
public enum SyncTrigger: String, Sendable {
    case signIn, foreground, workoutFinished, networkRestored, localChange, periodic, manual, background, retry
}

/// When to sync and how to retry (P045). Values follow docs/02-MIMARI.md §2.4.
public struct SyncSchedule: Sendable {
    public var debounce: Duration = .seconds(3)
    public var periodic: Duration = .seconds(15 * 60)
    public var backoffBase: TimeInterval = 2
    public var backoffMax: TimeInterval = 5 * 60

    public init() {}

    /// Exponential backoff with "equal jitter": half the step is fixed, half random. `random` is in 0..<1.
    public func backoff(attempt: Int, random: Double) -> TimeInterval {
        let step = min(backoffMax, backoffBase * pow(2, Double(max(0, attempt))))
        return step / 2 + step / 2 * random
    }
}

/// Runs the `SyncEngine` for the signed-in user: on the app's triggers, one pass at a time, with backoff, the first
/// restore and the sign-out wipe. The Profile screen reads its status.
@MainActor
@Observable
public final class SyncCoordinator {
    public enum Phase: Equatable, Sendable {
        case idle
        case syncing
        case restoring(SyncProgress)
        /// The last pass hit a transient error; a retry is scheduled.
        case waitingToRetry
        case failed(String)
    }

    public private(set) var phase: Phase = .idle
    public private(set) var lastSyncedAt: Date?
    public private(set) var pendingCount = 0
    public private(set) var failedCount = 0
    public private(set) var userId: UUID?
    /// False when this build has no server (no Supabase configuration, UI tests).
    public var isAvailable: Bool { engine != nil }

    @ObservationIgnored private let container: ModelContainer
    @ObservationIgnored private let metadata: SyncMetadataStore
    @ObservationIgnored private let makeEngine: @MainActor (UUID) -> SyncEngine?
    @ObservationIgnored private let schedule: SyncSchedule
    @ObservationIgnored private let sleep: @Sendable (Duration) async throws -> Void
    @ObservationIgnored private let random: @Sendable () -> Double
    @ObservationIgnored private let network: (@Sendable () -> AsyncStream<Bool>)?

    @ObservationIgnored private var engine: SyncEngine?
    @ObservationIgnored private var running: Task<Void, Never>?
    @ObservationIgnored private var rerun: (trigger: SyncTrigger, retryFailed: Bool)?
    @ObservationIgnored private var attempt = 0
    @ObservationIgnored private var retryTask: Task<Void, Never>?
    @ObservationIgnored private var debounceTask: Task<Void, Never>?
    @ObservationIgnored private var periodicTask: Task<Void, Never>?
    @ObservationIgnored private var networkTask: Task<Void, Never>?
    /// Passes started, for tests.
    @ObservationIgnored public private(set) var passCount = 0

    public init(
        modelContainer: ModelContainer, metadata: SyncMetadataStore, schedule: SyncSchedule = SyncSchedule(),
        network: (@Sendable () -> AsyncStream<Bool>)? = nil,
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
        random: @escaping @Sendable () -> Double = { Double.random(in: 0..<1) },
        makeEngine: @escaping @MainActor (UUID) -> SyncEngine?
    ) {
        container = modelContainer
        self.metadata = metadata
        self.schedule = schedule
        self.network = network
        self.sleep = sleep
        self.random = random
        self.makeEngine = makeEngine
    }

    // MARK: Session

    /// The user signed in (or the app started signed in). A store holding another account's rows is wiped first, so
    /// two accounts never mix; then the first restore (or a normal pass) runs.
    public func activate(userId: UUID) async {
        guard self.userId != userId else { return }
        cancelTimers()
        let local = SyncLocalStore(modelContainer: container)
        if (try? await local.hasRows(notOwnedBy: userId)) == true {
            try? await local.wipeAll()
        }
        if await metadata.snapshot.ownerUserId != userId { await metadata.reset(owner: userId) }
        self.userId = userId
        engine = makeEngine(userId)
        lastSyncedAt = await metadata.snapshot.lastSyncedAt
        observeNetwork()
        await refreshCounts()
        request(.signIn)
    }

    /// Rows not yet on the server, shown in the sign-out warning.
    public func unsyncedCount() async -> Int {
        await refreshCounts()
        return pendingCount + failedCount
    }

    /// Sign-out: stops syncing and deletes the user's rows from this device (the server keeps them).
    public func signOut() async {
        cancelTimers()
        networkTask?.cancel()
        networkTask = nil
        await running?.value
        engine = nil
        userId = nil
        try? await SyncLocalStore(modelContainer: container).wipeAll()
        await metadata.reset(owner: nil)
        phase = .idle
        lastSyncedAt = nil
        pendingCount = 0
        failedCount = 0
    }

    // MARK: Triggers

    /// Starts a pass now, or right after the running one. A `manual` pass also retries failed rows.
    public func request(_ trigger: SyncTrigger) {
        let retryFailed = trigger == .manual
        guard engine != nil else { return }
        if running != nil {
            rerun = (trigger, (rerun?.retryFailed ?? false) || retryFailed)
            return
        }
        retryTask?.cancel()
        retryTask = nil
        running = Task { await self.loop(trigger, retryFailed: retryFailed) }
    }

    /// A local write happened: sync a few seconds after the last one.
    public func noteLocalChange() {
        guard engine != nil else { return }
        debounceTask?.cancel()
        debounceTask = Task { [sleep, schedule] in
            do { try await sleep(schedule.debounce) } catch { return }
            self.request(.localChange)
        }
    }

    public func appBecameActive() {
        request(.foreground)
        periodicTask?.cancel()
        periodicTask = Task { [sleep, schedule] in
            while !Task.isCancelled {
                do { try await sleep(schedule.periodic) } catch { return }
                self.request(.periodic)
            }
        }
    }

    public func appEnteredBackground() {
        periodicTask?.cancel()
        periodicTask = nil
    }

    /// One pass for `BGAppRefreshTask`; true when it finished without error.
    public func backgroundSync() async -> Bool {
        request(.background)
        await running?.value
        if case .idle = phase { return true }
        return false
    }

    /// Waits for the running pass (tests, background task).
    public func waitUntilIdle() async {
        while let task = running { await task.value }
    }

    // MARK: Passes

    private func loop(_ first: SyncTrigger, retryFailed: Bool) async {
        var next: (trigger: SyncTrigger, retryFailed: Bool)? = (first, retryFailed)
        while let current = next, let engine {
            await pass(engine, trigger: current.trigger, retryFailed: current.retryFailed)
            next = rerun
            rerun = nil
        }
        running = nil
    }

    private func pass(_ engine: SyncEngine, trigger: SyncTrigger, retryFailed: Bool) async {
        if trigger == .localChange, (try? await engine.pendingCount()) == 0 { return }
        passCount += 1
        do {
            if await !metadata.snapshot.restoreCompleted {
                phase = .restoring(SyncProgress(done: 0, total: 0))
                let stream = AsyncStream<SyncProgress>.makeStream()
                let watcher = Task { for await value in stream.stream { self.phase = .restoring(value) } }
                try await engine.restore { stream.continuation.yield($0) }
                stream.continuation.finish()
                await watcher.value
            }
            phase = .syncing
            try await engine.sync(retryFailed: retryFailed)
            attempt = 0
            phase = .idle
            lastSyncedAt = await metadata.snapshot.lastSyncedAt
        } catch RemoteStoreError.transient(let reason) {
            Log.sync.info("Sync (\(trigger.rawValue, privacy: .public)) failed, will retry: \(reason, privacy: .public)")
            phase = .waitingToRetry
            scheduleRetry()
        } catch {
            Log.sync.error("Sync (\(trigger.rawValue, privacy: .public)) failed: \(String(describing: error), privacy: .public)")
            phase = .failed(String(describing: error))
        }
        await refreshCounts()
    }

    private func scheduleRetry() {
        let delay = schedule.backoff(attempt: attempt, random: random())
        attempt += 1
        retryTask?.cancel()
        retryTask = Task { [sleep] in
            do { try await sleep(.milliseconds(Int(delay * 1000))) } catch { return }
            self.request(.retry)
        }
    }

    private func refreshCounts() async {
        guard let engine else { return }
        pendingCount = (try? await engine.pendingCount()) ?? pendingCount
        failedCount = (try? await engine.failedCount()) ?? failedCount
    }

    private func observeNetwork() {
        networkTask?.cancel()
        guard let network else { return }
        networkTask = Task {
            var wasOnline = true
            for await online in network() {
                if online && !wasOnline { self.request(.networkRestored) }
                wasOnline = online
            }
        }
    }

    private func cancelTimers() {
        retryTask?.cancel()
        debounceTask?.cancel()
        periodicTask?.cancel()
        retryTask = nil
        debounceTask = nil
        periodicTask = nil
    }
}

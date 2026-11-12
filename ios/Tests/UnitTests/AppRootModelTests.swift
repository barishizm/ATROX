import Testing

@testable import ATROX

private struct FakeSessionService: SessionService {
    var result: Result<SessionStatus, any Error>
    func restoreSession() async throws -> SessionStatus { try result.get() }
    func signOut() async {}
}

private final class RecordingSessionService: SessionService, @unchecked Sendable {
    private(set) var completions = 0
    func restoreSession() async throws -> SessionStatus { .signedIn(onboardingComplete: false) }
    func signOut() async {}
    func markOnboardingComplete() async { completions += 1 }
}

private struct Boom: Error {}

@MainActor
struct AppRootModelTests {
    private func model(_ result: Result<SessionStatus, any Error>) -> AppRootModel {
        AppContainer(sessionService: FakeSessionService(result: result)).root
    }

    @Test func finishingOnboardingPersistsTheFlag() async {
        let service = RecordingSessionService()
        let m = AppContainer(sessionService: service).root
        await m.start()
        m.didCompleteOnboarding()
        await m.completionTask?.value
        #expect(m.state == .ready)
        #expect(service.completions == 1)
    }

    @Test func completionIsNotPersistedOutsideOnboarding() async {
        let service = RecordingSessionService()
        let m = AppContainer(sessionService: service).root
        m.didCompleteOnboarding()  // still .loading
        #expect(m.completionTask == nil)
        #expect(service.completions == 0)
    }

    @Test func startsLoading() {
        #expect(model(.success(.signedOut)).state == .loading)
    }

    @Test func restoreSignedOut() async {
        let m = model(.success(.signedOut))
        await m.start()
        #expect(m.state == .signedOut)
    }

    @Test func restoreWithoutOnboardingNeedsOnboarding() async {
        let m = model(.success(.signedIn(onboardingComplete: false)))
        await m.start()
        #expect(m.state == .needsOnboarding)
    }

    @Test func restoreWithOnboardingIsReady() async {
        let m = model(.success(.signedIn(onboardingComplete: true)))
        await m.start()
        #expect(m.state == .ready)
    }

    @Test func restoreFailureFallsBackToSignedOut() async {
        let m = model(.failure(Boom()))
        await m.start()
        #expect(m.state == .signedOut)
    }

    @Test func fullHappyPath() async {
        let m = model(.success(.signedOut))
        await m.start()
        m.didSignIn(onboardingComplete: false)
        #expect(m.state == .needsOnboarding)
        m.didCompleteOnboarding()
        #expect(m.state == .ready)
        await m.signOut()
        #expect(m.state == .signedOut)
    }

    @Test func returningUserSkipsOnboarding() async {
        let m = model(.success(.signedOut))
        await m.start()
        m.didSignIn(onboardingComplete: true)
        #expect(m.state == .ready)
    }

    @Test func signOutFromOnboarding() async {
        let m = model(.success(.signedIn(onboardingComplete: false)))
        await m.start()
        await m.signOut()
        #expect(m.state == .signedOut)
    }

    @Test func invalidTransitionsAreIgnored() async {
        let m = model(.success(.signedOut))
        await m.start()
        m.didCompleteOnboarding()
        #expect(m.state == .signedOut)
        await m.signOut()
        #expect(m.state == .signedOut)

        m.didSignIn(onboardingComplete: true)
        m.didSignIn(onboardingComplete: false)
        #expect(m.state == .ready)
        m.didCompleteOnboarding()
        #expect(m.state == .ready)
    }
}

// MARK: - Live session updates (P015)

private final class ScriptedSessionService: SessionService, @unchecked Sendable {
    let initial: SessionStatus
    private let pair = AsyncStream<SessionStatus>.makeStream()
    init(initial: SessionStatus) { self.initial = initial }
    func restoreSession() async throws -> SessionStatus { initial }
    func updates() -> AsyncStream<SessionStatus> { pair.stream }
    func signOut() async {}
    func emit(_ status: SessionStatus) { pair.continuation.yield(status) }
}

@MainActor
struct AppRootModelUpdatesTests {
    private func settle() async {
        for _ in 0..<20 { await Task.yield() }
    }

    @Test func remoteSignOutReturnsToSignedOut() async {
        let service = ScriptedSessionService(initial: .signedIn(onboardingComplete: true))
        let model = AppContainer(sessionService: service).root
        await model.start()
        #expect(model.state == .ready)
        service.emit(.signedOut)
        await settle()
        #expect(model.state == .signedOut)
    }

    @Test func signInEventMovesFromSignedOut() async {
        let service = ScriptedSessionService(initial: .signedOut)
        let model = AppContainer(sessionService: service).root
        await model.start()
        service.emit(.signedIn(onboardingComplete: false))
        await settle()
        #expect(model.state == .needsOnboarding)
    }

    @Test func refreshEventsDoNotDisturbTheScreen() async {
        let service = ScriptedSessionService(initial: .signedIn(onboardingComplete: false))
        let model = AppContainer(sessionService: service).root
        await model.start()
        service.emit(.signedIn(onboardingComplete: true))
        await settle()
        #expect(model.state == .needsOnboarding)
    }
}

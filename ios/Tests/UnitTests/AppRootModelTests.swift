import Testing

@testable import GymAnalyzer

private struct FakeSessionService: SessionService {
    var result: Result<SessionStatus, any Error>
    func restoreSession() async throws -> SessionStatus { try result.get() }
    func signOut() async {}
}

private struct Boom: Error {}

@MainActor
struct AppRootModelTests {
    private func model(_ result: Result<SessionStatus, any Error>) -> AppRootModel {
        AppContainer(sessionService: FakeSessionService(result: result)).root
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

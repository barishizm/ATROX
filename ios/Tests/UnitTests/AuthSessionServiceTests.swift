import DataKit
import Foundation
import Testing

@testable import ATROX

struct AuthSessionServiceTests {
    private let user = AuthUser(id: UUID(), email: "a@b.co", isEmailConfirmed: true, onboardingComplete: true)

    @Test func statusMapping() {
        #expect(AuthSessionService.status(for: .signedOut) == .signedOut)
        #expect(AuthSessionService.status(for: .signedIn(user)) == .signedIn(onboardingComplete: true))
        #expect(AuthSessionService.status(for: .passwordRecovery(user)) == .signedIn(onboardingComplete: true))
    }

    @Test func restoreUsesAuthState() async throws {
        let signedIn = AuthSessionService(auth: FakeAuthService(initial: .signedIn(user)))
        #expect(try await signedIn.restoreSession() == .signedIn(onboardingComplete: true))
        let signedOut = AuthSessionService(auth: FakeAuthService())
        #expect(try await signedOut.restoreSession() == .signedOut)
    }

    @Test func updatesFollowSignInAndSignOut() async throws {
        let fake = FakeAuthService()
        let service = AuthSessionService(auth: fake)
        var iterator = service.updates().makeAsyncIterator()
        #expect(await iterator.next() == .signedOut)
        _ = try await fake.signInWithApple()
        #expect(await iterator.next() == .signedIn(onboardingComplete: false))
        await service.signOut()
        #expect(await iterator.next() == .signedOut)
    }

    @MainActor
    @Test func rootFlowWithRealAdapterAndFakeBackend() async throws {
        let fake = FakeAuthService()
        let model = AppContainer(sessionService: AuthSessionService(auth: fake), authService: fake).root
        await model.start()
        #expect(model.state == .signedOut)
        _ = try await fake.signInWithGoogle()
        for _ in 0..<50 where model.state == .signedOut { await Task.yield() }
        #expect(model.state == .needsOnboarding)
        await model.signOut()
        #expect(model.state == .signedOut)
    }
}

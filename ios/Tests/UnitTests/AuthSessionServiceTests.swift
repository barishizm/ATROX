import DataKit
import Foundation
import Testing

@testable import GymAnalyzer

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

    // MARK: Onboarding completion survives a cold start (K1)

    private final class MemoryCompletionStore: OnboardingCompletionStore, @unchecked Sendable {
        private let lock = NSLock()
        private var ids: Set<UUID> = []
        func isComplete(userId: UUID) -> Bool { lock.withLock { ids.contains(userId) } }
        func markComplete(userId: UUID) { lock.withLock { _ = ids.insert(userId) } }
    }

    private let freshUser = AuthUser(id: UUID(), email: "a@b.co", isEmailConfirmed: true)

    @Test func finishedOnboardingIsRestoredAfterRelaunch() async throws {
        let fake = FakeAuthService(initial: .signedIn(freshUser))
        let store = MemoryCompletionStore()
        let first = AuthSessionService(auth: fake, completion: store)
        #expect(try await first.restoreSession() == .signedIn(onboardingComplete: false))

        await first.markOnboardingComplete()

        // "Relaunch": a new service over the same persisted state.
        let second = AuthSessionService(auth: fake, completion: store)
        #expect(try await second.restoreSession() == .signedIn(onboardingComplete: true))
        #expect(await fake.onboardingCompleteCount == 1)
    }

    @Test func serverFlagAloneIsEnoughOnAnotherDevice() async throws {
        let fake = FakeAuthService(initial: .signedIn(freshUser))
        await AuthSessionService(auth: fake, completion: MemoryCompletionStore()).markOnboardingComplete()
        let otherDevice = AuthSessionService(auth: fake, completion: MemoryCompletionStore())
        #expect(try await otherDevice.restoreSession() == .signedIn(onboardingComplete: true))
    }

    @Test func failedServerWriteStillSurvivesRelaunchAndIsRetried() async throws {
        let fake = FakeAuthService(initial: .signedIn(freshUser))
        let store = MemoryCompletionStore()
        let service = AuthSessionService(auth: fake, completion: store)
        await fake.setNextError(.offline)

        await service.markOnboardingComplete()
        #expect(await fake.onboardingCompleteCount == 0)

        #expect(try await service.restoreSession() == .signedIn(onboardingComplete: true))
        #expect(await fake.onboardingCompleteCount == 1)  // retried on the next launch
    }

    @Test func otherUsersAreNotAffected() async throws {
        let store = MemoryCompletionStore()
        await AuthSessionService(auth: FakeAuthService(initial: .signedIn(freshUser)), completion: store)
            .markOnboardingComplete()
        let someoneElse = AuthUser(id: UUID(), email: "c@d.co", isEmailConfirmed: true)
        let service = AuthSessionService(auth: FakeAuthService(initial: .signedIn(someoneElse)), completion: store)
        #expect(try await service.restoreSession() == .signedIn(onboardingComplete: false))
    }
}

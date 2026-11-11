import Foundation
import Testing

@testable import DataKit

struct FakeAuthServiceTests {
    private func firstValue(_ stream: AsyncStream<AuthState>) async -> AuthState? {
        for await value in stream { return value }
        return nil
    }

    @Test func restoreReturnsInitialState() async {
        let user = AuthUser(id: UUID(), email: "a@b.co", isEmailConfirmed: true)
        #expect(await FakeAuthService().restoreSession() == .signedOut)
        #expect(await FakeAuthService(initial: .signedIn(user)).restoreSession() == .signedIn(user))
    }

    @Test func signUpRequiresConfirmationThenSignIn() async throws {
        let service = FakeAuthService()
        let outcome = try await service.signUp(email: "a@b.co", password: "password1", locale: "tr")
        #expect(outcome == .confirmationRequired(email: "a@b.co"))
        #expect(await service.restoreSession() == .signedOut)

        await #expect(throws: AuthError.emailNotConfirmed) {
            try await service.signIn(email: "a@b.co", password: "password1")
        }
        await service.confirm(email: "a@b.co")
        let user = try await service.signIn(email: "a@b.co", password: "password1")
        #expect(await service.restoreSession() == .signedIn(user))
    }

    @Test func signUpWithoutConfirmationSignsInImmediately() async throws {
        let service = FakeAuthService()
        await service.setRequiresConfirmation(false)
        guard case .signedIn(let user) = try await service.signUp(email: "a@b.co", password: "password1", locale: nil)
        else { Issue.record("expected signedIn"); return }
        #expect(await service.restoreSession() == .signedIn(user))
    }

    @Test func wrongPasswordAndDuplicateAndWeak() async throws {
        let service = FakeAuthService()
        await service.setRequiresConfirmation(false)
        _ = try await service.signUp(email: "a@b.co", password: "password1", locale: nil)
        await #expect(throws: AuthError.invalidCredentials) { try await service.signIn(email: "a@b.co", password: "nope") }
        await #expect(throws: AuthError.emailAlreadyRegistered) {
            try await service.signUp(email: "a@b.co", password: "password1", locale: nil)
        }
        await #expect(throws: AuthError.weakPassword) {
            try await service.signUp(email: "c@d.co", password: "short", locale: nil)
        }
    }

    @Test func scriptedErrorIsConsumedOnce() async throws {
        let service = FakeAuthService()
        await service.setNextError(.offline)
        await #expect(throws: AuthError.offline) { try await service.signInWithApple() }
        _ = try await service.signInWithApple()
    }

    @Test func streamEmitsCurrentThenTransitions() async throws {
        let service = FakeAuthService()
        var iterator = service.stateUpdates().makeAsyncIterator()
        #expect(await iterator.next() == .signedOut)

        let user = try await service.signInWithGoogle()
        #expect(await iterator.next() == .signedIn(user))

        await service.signOut()
        #expect(await iterator.next() == .signedOut)
        #expect(await service.signOutCount == 1)
    }

    @Test func remoteSignOutReachesSubscribers() async throws {
        let service = FakeAuthService()
        _ = try await service.signInWithApple()
        var iterator = service.stateUpdates().makeAsyncIterator()
        guard case .signedIn? = await iterator.next() else { Issue.record("expected signedIn"); return }
        await service.simulateRemoteSignOut()
        #expect(await iterator.next() == .signedOut)
    }

    @Test func passwordResetIsRecorded() async throws {
        let service = FakeAuthService()
        try await service.sendPasswordReset(email: "a@b.co")
        #expect(await service.passwordResetRequests == ["a@b.co"])
    }
}

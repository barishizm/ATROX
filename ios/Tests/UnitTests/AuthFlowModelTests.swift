import DataKit
import Testing

@testable import ATROX

@MainActor
struct AuthFlowModelTests {
    private final class SignInRecorder {
        var users: [AuthUser] = []
    }

    private func make(
        _ fake: FakeAuthService = FakeAuthService(), cooldown: Int = 30
    ) -> (AuthFlowModel, SignInRecorder) {
        let recorder = SignInRecorder()
        let model = AuthFlowModel(
            service: fake, resendCooldown: cooldown, localeCode: { "tr" },
            onSignedIn: { recorder.users.append($0) }
        )
        return (model, recorder)
    }

    @Test func appleSignInReportsUser() async {
        let (model, recorder) = make()
        await model.signInWithApple()
        #expect(recorder.users.map(\.email) == ["apple@example.com"])
        #expect(model.error == nil)
        #expect(!model.isBusy)
    }

    @Test func googleFailureShowsError() async {
        let fake = FakeAuthService()
        await fake.setNextError(.providerUnavailable)
        let (model, recorder) = make(fake)
        await model.signInWithGoogle()
        #expect(model.error == .providerUnavailable)
        #expect(recorder.users.isEmpty)
    }

    @Test func cancelledProviderIsSilent() async {
        let fake = FakeAuthService()
        await fake.setNextError(.cancelled)
        let (model, _) = make(fake)
        await model.signInWithApple()
        #expect(model.error == nil)
    }

    @Test func signUpWithConfirmationPushesVerifyScreen() async {
        let (model, recorder) = make()
        model.path = [.signUp]
        await model.signUp(email: "  New@Example.com ", password: "Abcdef12")
        #expect(model.path == [.signUp, .verify(email: "new@example.com")])
        #expect(recorder.users.isEmpty)
        #expect(model.error == nil)
    }

    @Test func signUpWithoutConfirmationSignsIn() async {
        let fake = FakeAuthService()
        await fake.setRequiresConfirmation(false)
        let (model, recorder) = make(fake)
        await model.signUp(email: "a@b.co", password: "Abcdef12")
        #expect(recorder.users.count == 1)
        #expect(model.path.isEmpty)
    }

    @Test func signUpDuplicateShowsError() async {
        let (model, _) = make()
        await model.signUp(email: "a@b.co", password: "Abcdef12")
        await model.signUp(email: "a@b.co", password: "Abcdef12")
        #expect(model.error == .emailAlreadyRegistered)
    }

    @Test func wrongPasswordShowsInvalidCredentials() async {
        let fake = FakeAuthService()
        await fake.setRequiresConfirmation(false)
        _ = try? await fake.signUp(email: "a@b.co", password: "Abcdef12", locale: nil)
        let (model, recorder) = make(fake)
        await model.signIn(email: "a@b.co", password: "WrongPass1")
        #expect(model.error == .invalidCredentials)
        #expect(recorder.users.isEmpty)
        await model.signIn(email: "A@B.co", password: "Abcdef12")  // e-mail is normalized
        #expect(model.error == nil)
        #expect(recorder.users.count == 1)
    }

    @Test func unconfirmedSignInGoesToVerifyScreenWithoutError() async {
        let fake = FakeAuthService()
        _ = try? await fake.signUp(email: "a@b.co", password: "Abcdef12", locale: nil)
        let (model, recorder) = make(fake)
        await model.signIn(email: "a@b.co", password: "Abcdef12")
        #expect(model.path == [.verify(email: "a@b.co")])
        #expect(model.error == nil)
        #expect(recorder.users.isEmpty)
    }

    @Test func errorClearsOnNextAttempt() async {
        let fake = FakeAuthService()
        await fake.setNextError(.offline)
        let (model, _) = make(fake)
        await model.signInWithApple()
        #expect(model.error == .offline)
        await model.signInWithApple()
        #expect(model.error == nil)
    }

    @Test func passwordResetRecordsAddress() async {
        let fake = FakeAuthService()
        let (model, _) = make(fake)
        await model.sendPasswordReset(email: " Me@Example.com")
        #expect(model.resetSentTo == "me@example.com")
        #expect(await fake.passwordResetRequests == ["me@example.com"])
        model.resetPasswordResetState()
        #expect(model.resetSentTo == nil)
    }

    @Test func passwordResetFailureKeepsFormOpen() async {
        let fake = FakeAuthService()
        await fake.setNextError(.rateLimited)
        let (model, _) = make(fake)
        await model.sendPasswordReset(email: "me@example.com")
        #expect(model.resetSentTo == nil)
        #expect(model.error == .rateLimited)
    }

    @Test func resendStartsCooldownAndIgnoresTapsDuringIt() async {
        let (model, _) = make(cooldown: 30)
        await model.resendConfirmation(email: "a@b.co")
        #expect(model.didResend)
        #expect(model.resendCountdown == 30)
        await model.resendConfirmation(email: "a@b.co")  // still cooling down: no-op
        #expect(model.resendCountdown == 30)
    }

    @Test func resendFailureDoesNotStartCooldown() async {
        let fake = FakeAuthService()
        await fake.setNextError(.rateLimited)
        let (model, _) = make(fake)
        await model.resendConfirmation(email: "a@b.co")
        #expect(!model.didResend)
        #expect(model.resendCountdown == 0)
        #expect(model.error == .rateLimited)
    }

    @Test func showSignInReplacesStack() {
        let (model, _) = make()
        model.path = [.signUp, .verify(email: "a@b.co")]
        model.showSignIn(email: "a@b.co")
        #expect(model.path == [.signIn(email: "a@b.co")])
    }
}

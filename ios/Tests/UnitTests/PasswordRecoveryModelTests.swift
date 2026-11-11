import DataKit
import Foundation
import Testing

@testable import GymAnalyzer

@MainActor
struct PasswordRecoveryModelTests {
    private let user = AuthUser(id: UUID(), email: "a@b.co", isEmailConfirmed: true)

    @Test func recoveryStatePresentsScreen() {
        let model = PasswordRecoveryModel(service: FakeAuthService())
        model.apply(.signedIn(user))
        #expect(!model.isPresented)
        model.apply(.passwordRecovery(user))
        #expect(model.isPresented)
        model.apply(.signedIn(user))  // token refresh while the screen is open
        #expect(model.isPresented)
        model.apply(.signedOut)
        #expect(!model.isPresented)
    }

    @Test func successfulSubmitDismisses() async {
        let model = PasswordRecoveryModel(service: FakeAuthService())
        model.apply(.passwordRecovery(user))
        await model.submit(newPassword: "Abcdef12")
        #expect(!model.isPresented)
        #expect(model.error == nil)
    }

    @Test func rejectedPasswordKeepsScreenOpenWithError() async {
        let model = PasswordRecoveryModel(service: FakeAuthService())
        model.apply(.passwordRecovery(user))
        await model.submit(newPassword: "short")
        #expect(model.isPresented)
        #expect(model.error == .weakPassword)
        model.clearError()
        #expect(model.error == nil)
    }

    @Test func cancelSignsOut() async {
        let fake = FakeAuthService()
        let model = PasswordRecoveryModel(service: fake)
        model.apply(.passwordRecovery(user))
        await model.cancel()
        #expect(!model.isPresented)
        #expect(await fake.signOutCount == 1)
    }

    @Test func listenPresentsOnRecoveryEvent() async {
        let fake = FakeAuthService(initial: .passwordRecovery(user))
        let model = PasswordRecoveryModel(service: fake)
        let task = Task { await model.listen() }
        for _ in 0..<200 where !model.isPresented { try? await Task.sleep(for: .milliseconds(10)) }
        task.cancel()
        #expect(model.isPresented)
    }

    @Test func withoutServiceNothingHappens() async {
        let model = PasswordRecoveryModel(service: nil)
        await model.listen()
        await model.submit(newPassword: "Abcdef12")
        #expect(!model.isPresented)
    }
}

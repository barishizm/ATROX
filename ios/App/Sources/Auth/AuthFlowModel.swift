import DataKit
import Foundation
import Observation

/// Screens pushed on top of the welcome screen.
enum AuthRoute: Hashable {
    case signUp
    case signIn(email: String)
    case verify(email: String)
    case reset(email: String)
}

/// State and actions of the signed-out flow. Views stay dumb; every call goes through here.
@MainActor
@Observable
final class AuthFlowModel {
    /// What is in flight (drives the spinner on the tapped button and disables the rest).
    enum Action: Equatable, Sendable { case apple, google, email }

    var path: [AuthRoute] = []
    private(set) var busy: Action?
    private(set) var error: AuthError?
    /// Address the reset link was sent to (set once the request succeeded).
    private(set) var resetSentTo: String?
    /// Seconds until "resend" is available again; 0 = available.
    private(set) var resendCountdown = 0
    private(set) var didResend = false

    var isBusy: Bool { busy != nil }

    private let service: any AuthService
    private let onSignedIn: @MainActor (AuthUser) -> Void
    private let localeCode: @MainActor () -> String?
    private let resendCooldown: Int
    @ObservationIgnored private var cooldownTask: Task<Void, Never>?

    init(
        service: any AuthService,
        resendCooldown: Int = 30,
        localeCode: @escaping @MainActor () -> String? = { Locale.current.language.languageCode?.identifier },
        onSignedIn: @escaping @MainActor (AuthUser) -> Void
    ) {
        self.service = service
        self.resendCooldown = resendCooldown
        self.localeCode = localeCode
        self.onSignedIn = onSignedIn
    }

    deinit { cooldownTask?.cancel() }

    // MARK: Native providers

    func signInWithApple() async {
        await perform(.apple) { onSignedIn(try await service.signInWithApple()) }
    }

    func signInWithGoogle() async {
        await perform(.google) { onSignedIn(try await service.signInWithGoogle()) }
    }

    // MARK: E-mail

    func signUp(email: String, password: String) async {
        let email = AuthValidation.normalizedEmail(email)
        await perform(.email) {
            switch try await service.signUp(email: email, password: password, locale: localeCode()) {
            case .signedIn(let user): onSignedIn(user)
            case .confirmationRequired(let address): path.append(.verify(email: address))
            }
        }
    }

    func signIn(email: String, password: String) async {
        let email = AuthValidation.normalizedEmail(email)
        await perform(.email) {
            do {
                onSignedIn(try await service.signIn(email: email, password: password))
            } catch AuthError.emailNotConfirmed {
                // Not an error screen: the fix is on the verification screen (resend, then open the link).
                path.append(.verify(email: email))
            }
        }
    }

    func resendConfirmation(email: String) async {
        guard resendCountdown == 0 else { return }
        didResend = false
        let sent = await perform(.email) { try await service.resendConfirmation(email: email) }
        guard sent else { return }
        didResend = true
        startCooldown()
    }

    func sendPasswordReset(email: String) async {
        let email = AuthValidation.normalizedEmail(email)
        await perform(.email) {
            try await service.sendPasswordReset(email: email)
            resetSentTo = email
        }
    }

    // MARK: Navigation and state

    func clearError() { error = nil }

    /// Leaves the "link sent" state so the reset form can be used again.
    func resetPasswordResetState() { resetSentTo = nil }

    /// Replaces the stack with the sign-in form (after the user says they confirmed their e-mail).
    func showSignIn(email: String) { path = [.signIn(email: email)] }

    // MARK: Internals

    @discardableResult
    private func perform(_ action: Action, _ work: () async throws -> Void) async -> Bool {
        guard busy == nil else { return false }
        busy = action
        error = nil
        defer { busy = nil }
        do {
            try await work()
            return true
        } catch {
            let mapped = (error as? AuthError) ?? .unknown
            // Backing out of the Apple/Google sheet is a choice, not a failure.
            if mapped != .cancelled { self.error = mapped }
            return false
        }
    }

    private func startCooldown() {
        cooldownTask?.cancel()
        resendCountdown = resendCooldown
        guard resendCooldown > 0 else { return }
        cooldownTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, !Task.isCancelled else { return }
                resendCountdown = max(0, resendCountdown - 1)
                if resendCountdown == 0 { return }
            }
        }
    }
}

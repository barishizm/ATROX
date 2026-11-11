import DataKit
import Observation

/// Shows the "set a new password" screen when the user opens a password-reset link.
/// The SDK signs the user in with a recovery session; the root flow treats that as a normal session,
/// so this model presents the reset screen on top of whatever the root shows.
@MainActor
@Observable
final class PasswordRecoveryModel {
    private(set) var isPresented = false
    private(set) var isSaving = false
    private(set) var error: AuthError?

    private let service: (any AuthService)?

    /// `nil` when Supabase is not configured: nothing to listen to.
    init(service: (any AuthService)?) {
        self.service = service
    }

    func listen() async {
        guard let service else { return }
        for await state in service.stateUpdates() { apply(state) }
    }

    func apply(_ state: AuthState) {
        switch state {
        case .passwordRecovery:
            isPresented = true
        case .signedOut:
            isPresented = false
            error = nil
        case .signedIn:
            break  // Token refreshes must not dismiss the screen.
        }
    }

    func clearError() { error = nil }

    func submit(newPassword: String) async {
        guard let service, !isSaving else { return }
        isSaving = true
        error = nil
        defer { isSaving = false }
        do {
            try await service.updatePassword(newPassword)
            isPresented = false
        } catch {
            self.error = (error as? AuthError) ?? .unknown
        }
    }

    /// Abandons the reset. The recovery session is ended too, so a half-finished reset doesn't leave the user signed in.
    func cancel() async {
        isPresented = false
        error = nil
        await service?.signOut()
    }
}

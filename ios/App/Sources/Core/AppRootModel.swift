import Foundation
import Observation

/// What the root view shows.
enum SessionState: Sendable, Equatable {
    case loading
    case signedOut
    case needsOnboarding
    case ready
}

/// Drives the root flow: loading → signed out → onboarding → ready.
@MainActor
@Observable
final class AppRootModel {
    private(set) var state: SessionState = .loading

    private let service: any SessionService

    init(service: any SessionService) {
        self.service = service
    }

    /// Restores the session. A failed restore falls back to signed out.
    func start() async {
        state = .loading
        do {
            apply(try await service.restoreSession())
        } catch {
            Log.app.error("Session restore failed: \(error)")
            state = .signedOut
        }
    }

    /// Called by auth once the user has signed in or signed up.
    func didSignIn(onboardingComplete: Bool) {
        guard state == .signedOut || state == .loading else {
            return Log.app.info("Ignored didSignIn in state \(state)", privacy: .public)
        }
        apply(.signedIn(onboardingComplete: onboardingComplete))
    }

    func didCompleteOnboarding() {
        guard state == .needsOnboarding else {
            return Log.app.info("Ignored didCompleteOnboarding in state \(state)", privacy: .public)
        }
        state = .ready
    }

    func signOut() async {
        guard state == .needsOnboarding || state == .ready else {
            return Log.app.info("Ignored signOut in state \(state)", privacy: .public)
        }
        await service.signOut()
        state = .signedOut
    }

    private func apply(_ status: SessionStatus) {
        switch status {
        case .signedOut: state = .signedOut
        case .signedIn(let complete): state = complete ? .ready : .needsOnboarding
        }
    }
}

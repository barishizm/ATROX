import DesignSystem
import GoogleSignIn
import SwiftUI

/// Picks the screen for the current session state.
struct RootView: View {
    @Environment(AppContainer.self) private var container

    var body: some View {
        let root = container.root
        Group {
            switch root.state {
            case .loading: LoadingState()
            case .signedOut: AuthFlowView(model: container.authFlow)
            case .needsOnboarding: OnboardingFlowView()
            case .ready:
                MainTabView().overlay {
                    if let sync = container.sync, case .restoring(let progress) = sync.phase {
                        RestoreProgressView(progress: progress).transition(.opacity)
                    }
                }
            }
        }
        .animation(.default, value: root.state)
        .task { await root.start() }
        // Sync follows the session (P045): sign-in starts it (with the first restore).
        .task(id: root.state) { await container.sessionChanged(root.state) }
        .task { await container.passwordRecovery.listen() }
        .fullScreenCover(isPresented: .constant(container.passwordRecovery.isPresented)) {
            NewPasswordView(model: container.passwordRecovery)
        }
        .onOpenURL { url in
            // Google returns through its reversed-client-ID scheme; everything else is a Supabase auth link
            // (email confirmation, password reset) on the app's deep-link scheme.
            if GIDSignIn.sharedInstance.handle(url) { return }
            Task { _ = await container.authService?.handle(url: url) }
        }
    }
}

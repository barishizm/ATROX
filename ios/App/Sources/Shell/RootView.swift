import DesignSystem
import GoogleSignIn
import SwiftUI

/// Picks the screen for the current session state.
struct RootView: View {
    @Environment(AppContainer.self) private var container
    @State private var handledEpoch = 0

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
        .id(root.epoch)
        .animation(.default, value: root.state)
        .task { await root.start() }
        // Sync follows the session (P045): sign-in starts it (with the first restore).
        .task(id: SessionKey(state: root.state, epoch: root.epoch)) {
            // A session that was swapped for another account in one step never showed `.signedOut`: end it here.
            if root.epoch != handledEpoch {
                handledEpoch = root.epoch
                await container.sessionEndedExternally()
            }
            await container.sessionChanged(root.state)
        }
        .task { await container.passwordRecovery.listen() }
        .fullScreenCover(
            isPresented: Binding(
                get: { container.passwordRecovery.isPresented },
                set: { shown in if !shown, container.passwordRecovery.isPresented { Task { await container.passwordRecovery.cancel() } } }
            )
        ) {
            NewPasswordView(model: container.passwordRecovery)
        }
        .onOpenURL { url in
            // Google returns through its reversed-client-ID scheme; everything else is a Supabase auth link
            // (email confirmation, password reset) on the app's deep-link scheme.
            if GIDSignIn.sharedInstance.handle(url) { return }
            // Navigation links (friend invites, tabs) wait in the router until the main shell is up.
            if container.deepLinks.receive(url: url) { return }
            Task { _ = await container.authService?.handle(url: url) }
        }
    }
}

private struct SessionKey: Hashable {
    let state: SessionState
    let epoch: Int
}

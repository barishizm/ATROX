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
            case .signedOut: AuthPlaceholderView()
            case .needsOnboarding: OnboardingPlaceholderView()
            case .ready: MainTabView()
            }
        }
        .animation(.default, value: root.state)
        .task { await root.start() }
        .onOpenURL { url in
            // Google returns through its reversed-client-ID scheme; everything else is a Supabase auth link
            // (email confirmation, password reset) on the app's deep-link scheme.
            if GIDSignIn.sharedInstance.handle(url) { return }
            Task { _ = await container.authService?.handle(url: url) }
        }
    }
}

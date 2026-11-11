import DesignSystem
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
    }
}

import DesignSystem
import SwiftUI

/// Placeholder for the sign-in flow (real screens: P016).
struct AuthPlaceholderView: View {
    @Environment(AppContainer.self) private var container
    @State private var showDebugMenu = false

    var body: some View {
        VStack(spacing: Spacing.lg) {
            FeaturePlaceholderView(title: "auth.title", systemImage: "person.crop.circle")
            #if DEBUG
            Button("auth.debug.continue") {
                container.root.didSignIn(onboardingComplete: false)
            }
            .accessibilityIdentifier("auth-debug-continue")
            Button("debug.menu.open") { showDebugMenu = true }
                .accessibilityIdentifier("auth-debug-menu")
                .padding(.bottom, Spacing.xl)
            #endif
        }
        .background(DSColor.background)
        #if DEBUG
        .sheet(isPresented: $showDebugMenu) { DebugMenuView() }
        #endif
    }
}

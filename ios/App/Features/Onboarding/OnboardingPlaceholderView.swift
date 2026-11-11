import DesignSystem
import SwiftUI

/// Placeholder for onboarding (real screens: P0xx).
struct OnboardingPlaceholderView: View {
    @Environment(AppContainer.self) private var container

    var body: some View {
        VStack(spacing: Spacing.lg) {
            FeaturePlaceholderView(title: "onboarding.title", systemImage: "figure.strengthtraining.traditional")
            #if DEBUG
            Button("onboarding.debug.finish") {
                container.root.didCompleteOnboarding()
            }
            .accessibilityIdentifier("onboarding-debug-finish")
            .padding(.bottom, Spacing.xl)
            #endif
        }
        .background(DSColor.background)
    }
}

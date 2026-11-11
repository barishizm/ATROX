import DesignSystem
import SwiftUI

/// First screen: value proposition and the three ways in. Apple is first, per Apple's guidelines.
struct WelcomeView: View {
    let model: AuthFlowModel
    var legal: LegalLinks = .current

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.xl) {
                header
                features
                actions
                LegalLinksView(links: legal)
                #if DEBUG
                AuthDebugTools()
                #endif
            }
            .padding(Spacing.lg)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(DSColor.background)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { model.clearError() }
        .accessibilityIdentifier("auth-welcome")
    }

    private var header: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "figure.strengthtraining.traditional")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(DSColor.onAccent)
                .frame(width: 88, height: 88)
                .background(DSColor.accent, in: RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
                .accessibilityHidden(true)
            Text("auth.welcome.headline")
                .font(DSFont.title)
                .foregroundStyle(DSColor.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Text("auth.welcome.subheadline")
                .font(DSFont.callout)
                .foregroundStyle(DSColor.textSecondary)
        }
        .multilineTextAlignment(.center)
        .padding(.top, Spacing.xl)
    }

    private var features: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            FeatureRow(systemImage: "gauge.with.dots.needle.67percent", title: "auth.welcome.feature.score")
            FeatureRow(systemImage: "sparkles", title: "auth.welcome.feature.coach")
            FeatureRow(systemImage: "chart.line.uptrend.xyaxis", title: "auth.welcome.feature.progress")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Spacing.sm)
    }

    private var actions: some View {
        VStack(spacing: Spacing.md) {
            AppleSignInButton { Task { await model.signInWithApple() } }
                .frame(height: HitTarget.button)
                .disabled(model.isBusy)
                .overlay { if model.busy == .apple { ProgressView().tint(.gray) } }
                .accessibilityIdentifier("welcome-apple")
            SecondaryButton("auth.welcome.google", isLoading: model.busy == .google) {
                Task { await model.signInWithGoogle() }
            }
            .disabled(model.isBusy)
            .accessibilityIdentifier("welcome-google")
            SecondaryButton("auth.welcome.email", systemImage: "envelope.fill") {
                model.path.append(.signUp)
            }
            .disabled(model.isBusy)
            .accessibilityIdentifier("welcome-email")
            if let error = model.error { AuthErrorBanner(error: error) }
            HStack(spacing: Spacing.xs) {
                Text("auth.welcome.haveAccount").foregroundStyle(DSColor.textSecondary)
                Button("auth.welcome.signIn") { model.path.append(.signIn(email: "")) }
                    .fontWeight(.semibold)
                    .disabled(model.isBusy)
                    .accessibilityIdentifier("welcome-signin")
            }
            .font(DSFont.callout)
            .frame(minHeight: HitTarget.minimum)
        }
    }
}

private struct FeatureRow: View {
    let systemImage: String
    let title: LocalizedStringKey

    var body: some View {
        Label {
            Text(title).font(DSFont.body).foregroundStyle(DSColor.textPrimary)
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(DSColor.accent)
                .frame(width: 28)
        }
    }
}

#if DEBUG
/// Developer shortcuts (compiled out of Staging/Release): skip auth, open the debug menu.
private struct AuthDebugTools: View {
    @Environment(AppContainer.self) private var container
    @State private var showDebugMenu = false

    var body: some View {
        VStack(spacing: Spacing.xs) {
            Button("auth.signin.debugContinue") { container.root.didSignIn(onboardingComplete: false) }
                .accessibilityIdentifier("auth-debug-continue")
            Button("debug.menu.open") { showDebugMenu = true }
                .accessibilityIdentifier("auth-debug-menu")
        }
        .font(DSFont.caption)
        .sheet(isPresented: $showDebugMenu) { DebugMenuView() }
    }
}
#endif

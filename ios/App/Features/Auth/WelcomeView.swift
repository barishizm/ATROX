import DesignSystem
import SwiftUI

/// First screen: the mascot talks the user through the start, one short line at a time.
/// Tapping anywhere moves to the next line; the last line asks "do you already have an account?"
/// and is the only step with buttons (→ sign-up methods or sign-in methods).
struct WelcomeView: View {
    let model: AuthFlowModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var step: Step = .greeting

    private enum Step { case greeting, plan, question }

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: Spacing.xl) {
                    Spacer(minLength: 0)
                    content
                    Spacer(minLength: 0)
                    footer
                    #if DEBUG
                    AuthDebugTools()
                    #endif
                }
                .padding(Spacing.lg)
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity, minHeight: proxy.size.height)
                .contentShape(Rectangle())
                .onTapGesture { advance() }
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .background(DSColor.background)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { model.clearError() }
        .accessibilityIdentifier("auth-welcome")
    }

    @ViewBuilder private var content: some View {
        switch step {
        case .greeting:
            MascotSpeech(image: "MascotExcited", message: "auth.intro.greeting", mascotWidth: 240)
                .transition(.opacity)
        case .plan:
            MascotSpeech(image: "MascotHappy", message: "auth.intro.plan", mascotWidth: 240)
                .transition(.opacity)
        case .question:
            MascotSpeech(image: "MascotCool", message: "auth.intro.question", mascotWidth: 240)
                .transition(.opacity)
        }
    }

    @ViewBuilder private var footer: some View {
        if step == .question {
            VStack(spacing: Spacing.md) {
                PrimaryButton("auth.intro.continue") { model.path.append(.quiz) }
                    .accessibilityIdentifier("welcome-continue")
                SecondaryButton("auth.intro.haveAccount") { model.path.append(.methods(.signIn)) }
                    .accessibilityIdentifier("welcome-have-account")
            }
        } else {
            Text("auth.intro.tapHint")
                .font(DSFont.callout)
                .foregroundStyle(DSColor.textTertiary)
                .frame(minHeight: HitTarget.button)
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { advance() }
        }
    }

    private func advance() {
        let next: Step
        switch step {
        case .greeting: next = .plan
        case .plan: next = .question
        case .question: return
        }
        if reduceMotion { step = next } else { withAnimation(.easeInOut(duration: 0.3)) { step = next } }
    }
}

/// How to get in: Apple first (per Apple's guidelines), then Google, then e-mail. Same screen for
/// sign-up and sign-in; only the mascot's line and the e-mail destination differ.
struct AuthMethodsView: View {
    let model: AuthFlowModel
    let mode: AuthMode
    /// Shown as the first screen (no intro in front of it): offer a way over to sign-in.
    var isRoot = false
    var legal: LegalLinks = .current

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.xl) {
                MascotSpeech(
                    image: mode == .signUp ? "MascotExcited" : "MascotCool",
                    message: mode == .signUp ? "auth.methods.signUp" : "auth.methods.signIn",
                    mascotWidth: 160
                )
                actions
                LegalLinksView(links: legal)
                #if DEBUG
                if isRoot { AuthDebugTools() }
                #endif
            }
            .padding(Spacing.lg)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(DSColor.background)
        .toolbar(isRoot ? .hidden : .automatic, for: .navigationBar)
        .onAppear { model.clearError() }
        .accessibilityIdentifier(mode == .signUp ? "auth-methods-signup" : "auth-methods-signin")
    }

    private var actions: some View {
        VStack(spacing: Spacing.md) {
            AppleSignInButton { Task { await model.signInWithApple() } }
                .frame(height: HitTarget.button)
                .disabled(model.isBusy)
                .overlay { if model.busy == .apple { ProgressView().tint(.gray) } }
                .accessibilityIdentifier("welcome-apple")
            SecondaryButton("auth.welcome.google", icon: Image("GoogleLogo"), isLoading: model.busy == .google) {
                Task { await model.signInWithGoogle() }
            }
            .disabled(model.isBusy)
            .accessibilityIdentifier("welcome-google")
            SecondaryButton(mode == .signUp ? "auth.welcome.email" : "auth.methods.emailSignIn", systemImage: "envelope.fill") {
                model.path.append(mode == .signUp ? .signUp : .signIn(email: ""))
            }
            .disabled(model.isBusy)
            .accessibilityIdentifier("welcome-email")
            if let error = model.error { AuthErrorBanner(error: error) }
            if mode == .signUp {
                // Sign-up is the last step of the questions; people who already have an account must not have to
                // backtrack through them, so the way over to sign-in is offered right here.
                VStack(spacing: Spacing.xs) {
                    Text("auth.methods.haveAccount").foregroundStyle(DSColor.textSecondary)
                    Button("auth.welcome.signIn") {
                        model.path.append(isRoot ? .signIn(email: "") : .methods(.signIn))
                    }
                    .fontWeight(.semibold)
                    .disabled(model.isBusy)
                    .accessibilityIdentifier("welcome-signin")
                }
                .font(DSFont.callout)
                .frame(minHeight: HitTarget.minimum)
            }
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
            Button("auth.signin.debugContinue") { container.debugSignIn() }
                .accessibilityIdentifier("auth-debug-continue")
            Button("debug.menu.open") { showDebugMenu = true }
                .accessibilityIdentifier("auth-debug-menu")
        }
        .font(DSFont.caption)
        .sheet(isPresented: $showDebugMenu) { DebugMenuView() }
    }
}
#endif

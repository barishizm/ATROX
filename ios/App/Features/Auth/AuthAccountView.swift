import DesignSystem
import SwiftUI

/// One screen for both ways in: the register form, and (after "Log in" at the bottom) the log-in form in the
/// same place. Apple and Google sit under the form in both modes.
struct AuthAccountView: View {
    let model: AuthFlowModel
    @State private var mode: AuthMode
    @State private var email = ""
    @State private var password = ""
    @FocusState private var focus: AuthField?
    var legal: LegalLinks = .current

    init(model: AuthFlowModel, mode: AuthMode = .signUp) {
        self.model = model
        _mode = State(initialValue: mode)
    }

    private var isSignUp: Bool { mode == .signUp }
    private var emailIsValid: Bool { AuthValidation.isValidEmail(email) }
    private var canSubmit: Bool {
        isSignUp ? emailIsValid && PasswordRules(password).isSatisfied : emailIsValid && !password.isEmpty
    }
    private var showEmailHint: Bool { isSignUp && !email.isEmpty && !emailIsValid && focus != .email }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                form
                if let error = model.error { AuthErrorBanner(error: error) }
                submitButton
                divider
                providers
                switchMode
                LegalLinksView(links: legal)
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.bottom, Spacing.md)
            .frame(maxWidth: 520, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .scrollBounceBehavior(.basedOnSize)
        .background(DSColor.background)
        .navigationBarTitleDisplayMode(.inline)
        .disabled(model.busy == .email)
        .onAppear { model.clearError() }
        .accessibilityIdentifier(isSignUp ? "auth-account-signup" : "auth-account-signin")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(isSignUp ? "auth.signup.title" : "auth.signin.title")
                .font(DSFont.title)
                .foregroundStyle(DSColor.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Text(isSignUp ? "auth.signup.subtitle" : "auth.signin.subtitle")
                .font(DSFont.callout)
                .foregroundStyle(DSColor.textSecondary)
        }
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            AuthTextField(
                title: "auth.field.email", text: $email, field: .email, focus: $focus,
                contentType: .username, keyboard: .emailAddress,
                placeholder: "auth.field.email.placeholder", identifier: "auth-email-field",
                onSubmit: { focus = .password }
            )
            if showEmailHint {
                Text("auth.field.email.invalid").font(DSFont.footnote).foregroundStyle(DSColor.error)
                    .accessibilityIdentifier("auth-email-hint")
            }
            AuthTextField(
                title: "auth.field.password", text: $password, field: .password, focus: $focus,
                isSecure: true, contentType: isSignUp ? .newPassword : .password, submitLabel: .go,
                identifier: "auth-password-field", onSubmit: submit
            )
            if isSignUp {
                PasswordStrengthView(password: password, compact: true)
            } else {
                Button("auth.signin.forgot") { model.path.append(.reset(email: email)) }
                    .font(DSFont.callout.weight(.semibold))
                    .frame(minHeight: HitTarget.minimum)
                    .accessibilityIdentifier("auth-forgot")
            }
        }
    }

    private var submitButton: some View {
        PrimaryButton(isSignUp ? "auth.signup.submit" : "auth.signin.submit", isLoading: model.busy == .email, action: submit)
            .disabled(!canSubmit || model.isBusy)
            .accessibilityIdentifier("auth-submit")
    }

    private var divider: some View {
        HStack(spacing: Spacing.md) {
            Rectangle().fill(DSColor.separator).frame(height: 1)
            Text("auth.account.or").font(DSFont.footnote).foregroundStyle(DSColor.textSecondary)
            Rectangle().fill(DSColor.separator).frame(height: 1)
        }
        .accessibilityHidden(true)
    }

    private var providers: some View {
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
        }
    }

    /// Bottom link: flips the same screen between register and log in.
    private var switchMode: some View {
        VStack(spacing: Spacing.xs) {
            Text(isSignUp ? "auth.methods.haveAccount" : "auth.account.noAccount")
                .foregroundStyle(DSColor.textSecondary)
            Button(isSignUp ? "auth.account.logIn" : "auth.account.register") {
                focus = nil
                model.clearError()
                password = ""
                withAnimation(.easeInOut(duration: 0.2)) { mode = isSignUp ? .signIn : .signUp }
            }
            .fontWeight(.semibold)
            .disabled(model.isBusy)
            .accessibilityIdentifier("auth-switch-mode")
        }
        .font(DSFont.callout)
        .frame(maxWidth: .infinity, minHeight: HitTarget.minimum)
    }

    private func submit() {
        guard canSubmit, !model.isBusy else { return }
        focus = nil
        Task {
            if isSignUp {
                await model.signUp(email: email, password: password)
            } else {
                await model.signIn(email: email, password: password)
            }
        }
    }
}

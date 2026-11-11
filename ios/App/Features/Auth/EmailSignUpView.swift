import DesignSystem
import SwiftUI

/// E-mail registration. The password field uses `.newPassword`, which offers iOS's strong-password suggestion.
struct EmailSignUpView: View {
    let model: AuthFlowModel
    @State private var email = ""
    @State private var password = ""
    @FocusState private var focus: AuthField?

    private var emailIsValid: Bool { AuthValidation.isValidEmail(email) }
    private var canSubmit: Bool { emailIsValid && PasswordRules(password).isSatisfied }
    private var showEmailHint: Bool { !email.isEmpty && !emailIsValid && focus != .email }

    var body: some View {
        AuthScreen(title: "auth.signup.title", subtitle: "auth.signup.subtitle") {
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
                    isSecure: true, contentType: .newPassword, submitLabel: .go,
                    identifier: "auth-password-field", onSubmit: submit
                )
                PasswordStrengthView(password: password)
            }
            if let error = model.error { AuthErrorBanner(error: error) }
            PrimaryButton("auth.signup.submit", isLoading: model.busy == .email, action: submit)
                .disabled(!canSubmit || model.isBusy)
                .accessibilityIdentifier("auth-submit")
        }
        .disabled(model.busy == .email)
        .onAppear { model.clearError() }
    }

    private func submit() {
        guard canSubmit, !model.isBusy else { return }
        focus = nil
        Task { await model.signUp(email: email, password: password) }
    }
}

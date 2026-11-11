import DesignSystem
import SwiftUI

/// Requests a password-reset e-mail. The confirmation never says whether the address has an account.
struct PasswordResetView: View {
    let model: AuthFlowModel
    @State private var email: String
    @FocusState private var focus: AuthField?

    init(model: AuthFlowModel, email: String) {
        self.model = model
        _email = State(initialValue: email)
    }

    private var canSubmit: Bool { AuthValidation.isValidEmail(email) }

    var body: some View {
        AuthScreen(title: "auth.reset.title", subtitle: model.resetSentTo == nil ? "auth.reset.subtitle" : nil) {
            if let sentTo = model.resetSentTo {
                sentState(sentTo)
            } else {
                form
            }
        }
        .disabled(model.busy == .email)
        .onAppear {
            model.clearError()
            model.resetPasswordResetState()
        }
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            AuthTextField(
                title: "auth.field.email", text: $email, field: .email, focus: $focus,
                contentType: .username, keyboard: .emailAddress, submitLabel: .send,
                placeholder: "auth.field.email.placeholder", identifier: "auth-email-field", onSubmit: submit
            )
            if let error = model.error { AuthErrorBanner(error: error) }
            PrimaryButton("auth.reset.submit", isLoading: model.busy == .email, action: submit)
                .disabled(!canSubmit || model.isBusy)
                .accessibilityIdentifier("auth-submit")
        }
    }

    private func sentState(_ address: String) -> some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            Label("auth.reset.sent.title", systemImage: "paperplane.fill")
                .font(DSFont.headline)
                .foregroundStyle(DSColor.accent)
            Text("auth.reset.sent.message \(address)")
                .font(DSFont.body)
                .foregroundStyle(DSColor.textPrimary)
                .accessibilityIdentifier("reset-sent-message")
            SecondaryButton("auth.reset.backToSignIn") { model.showSignIn(email: address) }
                .accessibilityIdentifier("reset-back")
        }
    }

    private func submit() {
        guard canSubmit, !model.isBusy else { return }
        focus = nil
        Task { await model.sendPasswordReset(email: email) }
    }
}

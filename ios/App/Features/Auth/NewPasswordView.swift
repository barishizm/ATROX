import DesignSystem
import SwiftUI

/// Presented over the app when the user opens a password-reset link (see `PasswordRecoveryModel`).
struct NewPasswordView: View {
    let model: PasswordRecoveryModel
    @State private var password = ""
    @FocusState private var focus: AuthField?

    private var canSubmit: Bool { PasswordRules(password).isSatisfied }

    var body: some View {
        NavigationStack {
            AuthScreen(title: "auth.newPassword.title", subtitle: "auth.newPassword.subtitle") {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    AuthTextField(
                        title: "auth.field.newPassword", text: $password, field: .password, focus: $focus,
                        isSecure: true, contentType: .newPassword, submitLabel: .go,
                        identifier: "auth-password-field", onSubmit: submit
                    )
                    PasswordStrengthView(password: password)
                }
                if let error = model.error { AuthErrorBanner(error: error) }
                PrimaryButton("auth.newPassword.submit", isLoading: model.isSaving, action: submit)
                    .disabled(!canSubmit || model.isSaving)
                    .accessibilityIdentifier("auth-submit")
            }
            .disabled(model.isSaving)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("auth.newPassword.cancel") { Task { await model.cancel() } }
                        .accessibilityIdentifier("newpassword-cancel")
                }
            }
        }
        .onAppear { model.clearError() }
    }

    private func submit() {
        guard canSubmit, !model.isSaving else { return }
        focus = nil
        Task { await model.submit(newPassword: password) }
    }
}

import DesignSystem
import SwiftUI

struct EmailSignInView: View {
    let model: AuthFlowModel
    @State private var email: String
    @State private var password = ""
    @FocusState private var focus: AuthField?

    init(model: AuthFlowModel, email: String) {
        self.model = model
        _email = State(initialValue: email)
    }

    private var canSubmit: Bool { AuthValidation.isValidEmail(email) && !password.isEmpty }

    var body: some View {
        AuthScreen(title: "auth.signin.title", subtitle: "auth.signin.subtitle") {
            VStack(alignment: .leading, spacing: Spacing.md) {
                AuthTextField(
                    title: "auth.field.email", text: $email, field: .email, focus: $focus,
                    contentType: .username, keyboard: .emailAddress,
                    placeholder: "auth.field.email.placeholder", identifier: "auth-email-field",
                    onSubmit: { focus = .password }
                )
                AuthTextField(
                    title: "auth.field.password", text: $password, field: .password, focus: $focus,
                    isSecure: true, contentType: .password, submitLabel: .go,
                    identifier: "auth-password-field", onSubmit: submit
                )
                Button("auth.signin.forgot") { model.path.append(.reset(email: email)) }
                    .font(DSFont.callout.weight(.semibold))
                    .frame(minHeight: HitTarget.minimum)
                    .accessibilityIdentifier("auth-forgot")
            }
            if let error = model.error { AuthErrorBanner(error: error) }
            PrimaryButton("auth.signin.submit", isLoading: model.busy == .email, action: submit)
                .disabled(!canSubmit || model.isBusy)
                .accessibilityIdentifier("auth-submit")
        }
        .disabled(model.busy == .email)
        .onAppear { model.clearError() }
    }

    private func submit() {
        guard canSubmit, !model.isBusy else { return }
        focus = nil
        Task { await model.signIn(email: email, password: password) }
    }
}

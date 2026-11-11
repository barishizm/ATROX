import DesignSystem
import SwiftUI

/// Shown after sign-up (or a sign-in with an unconfirmed address). Opening the link in the mail signs the user in
/// through the deep link, and the root flow then replaces this whole stack.
struct VerificationPendingView: View {
    let model: AuthFlowModel
    let email: String

    var body: some View {
        AuthScreen(title: "auth.verify.title", subtitle: nil) {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                Image(systemName: "envelope.badge")
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundStyle(DSColor.accent)
                    .accessibilityHidden(true)
                Text("auth.verify.message \(email)")
                    .font(DSFont.body)
                    .foregroundStyle(DSColor.textPrimary)
                    .accessibilityIdentifier("verify-message")
                Text("auth.verify.spamHint").font(DSFont.footnote).foregroundStyle(DSColor.textSecondary)
            }
            if let error = model.error { AuthErrorBanner(error: error) }
            if model.didResend && model.error == nil {
                Label("auth.verify.resent", systemImage: "checkmark.circle.fill")
                    .font(DSFont.callout)
                    .foregroundStyle(DSColor.success)
                    .accessibilityIdentifier("verify-resent")
            }
            VStack(spacing: Spacing.md) {
                PrimaryButton("auth.verify.confirmedSignIn") { model.showSignIn(email: email) }
                    .accessibilityIdentifier("verify-signin")
                resendButton
                Button("auth.verify.changeEmail") { model.path.removeLast() }
                    .font(DSFont.callout.weight(.semibold))
                    .frame(minHeight: HitTarget.minimum)
                    .accessibilityIdentifier("verify-change-email")
            }
        }
        .accessibilityIdentifier("verify-screen")
        .onAppear { model.clearError() }
    }

    @ViewBuilder private var resendButton: some View {
        let cooling = model.resendCountdown > 0
        SecondaryButton(
            title: cooling ? Text("auth.verify.resendIn \(model.resendCountdown)") : Text("auth.verify.resend"),
            systemImage: cooling ? nil : "arrow.clockwise",
            isLoading: model.busy == .email
        ) {
            Task { await model.resendConfirmation(email: email) }
        }
        .disabled(cooling || model.isBusy)
        .accessibilityIdentifier("verify-resend")
    }
}

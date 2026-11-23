import DesignSystem
import SwiftUI
import UIKit

/// Shown after sign-up (or a sign-in with an unconfirmed address). Opening the link in the mail signs the user in
/// through the deep link, and the root flow then replaces this whole stack.
struct VerificationPendingView: View {
    let model: AuthFlowModel
    let email: String
    @Environment(\.openURL) private var openURL
    @State private var mailChoices: [MailApp] = []
    @State private var showMailChoices = false

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
                SecondaryButton(title: Text("auth.verify.openMail"), systemImage: "envelope.open", isLoading: false) {
                    openMail()
                }
                .accessibilityIdentifier("verify-open-mail")
                .confirmationDialog("auth.verify.openMail", isPresented: $showMailChoices, titleVisibility: .visible) {
                    ForEach(mailChoices) { app in
                        Button(app.name) { openURL(app.url) }
                    }
                }
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

    /// iOS has no API to open the user's default mail app on its inbox (`message://` is always Apple Mail), so
    /// open the one installed mail app directly, or let the user pick when several are installed.
    private func openMail() {
        let installed = MailApp.installed
        switch installed.count {
        case 0: if let url = URL(string: "mailto:") { openURL(url) }
        case 1: openURL(installed[0].url)
        default:
            mailChoices = installed
            showMailChoices = true
        }
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

/// Mail clients that can open straight to the inbox. Every scheme here must also be listed in
/// `LSApplicationQueriesSchemes` (project.yml) or `canOpenURL` always answers false.
private struct MailApp: Identifiable {
    let name: String
    let scheme: String
    var id: String { scheme }
    var url: URL { URL(string: "\(scheme)://")! }

    private static let all = [
        MailApp(name: "Mail", scheme: "message"),
        MailApp(name: "Gmail", scheme: "googlegmail"),
        MailApp(name: "Outlook", scheme: "ms-outlook"),
        MailApp(name: "Yahoo Mail", scheme: "ymail"),
        MailApp(name: "Spark", scheme: "readdle-spark"),
        MailApp(name: "Proton Mail", scheme: "protonmail")
    ]

    @MainActor static var installed: [MailApp] {
        all.filter { UIApplication.shared.canOpenURL($0.url) }
    }
}

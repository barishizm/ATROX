import DesignSystem
import SwiftUI

/// Two-step account deletion: an explanation, then typing the confirmation word.
struct DeleteAccountView: View {
    @Bindable var account: AccountModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var fieldFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(DSColor.error)
                    .accessibilityHidden(true)
                if account.deletionStep == .confirm { confirmStep } else { explainStep }
            }
            .padding(Spacing.lg)
            .frame(maxWidth: 520, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(DSColor.background)
        .navigationTitle("account.delete.title")
        .navigationBarTitleDisplayMode(.inline)
        .task { if account.deletionStep == nil { account.beginDeletion() } }
        .onDisappear { account.cancelDeletion() }
        .animation(.snappy, value: account.deletionStep)
        .accessibilityIdentifier("delete-account-screen")
    }

    private var explainStep: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("account.delete.explain.title").font(DSFont.title).foregroundStyle(DSColor.textPrimary)
            Text("account.delete.explain.body").font(DSFont.body).foregroundStyle(DSColor.textSecondary)
            PrimaryButton("account.delete.continue") { account.continueToConfirmation() }
                .accessibilityIdentifier("delete-continue")
            SecondaryButton("common.cancel") { dismiss() }
        }
    }

    private var confirmStep: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("account.delete.confirm.title").font(DSFont.title).foregroundStyle(DSColor.textPrimary)
            Text("account.delete.confirm.prompt \(account.confirmationWord)")
                .font(DSFont.body)
                .foregroundStyle(DSColor.textSecondary)
            TextField("", text: $account.confirmationText)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .focused($fieldFocused)
                .padding(.horizontal, Spacing.md)
                .frame(minHeight: HitTarget.button)
                .background(DSColor.surfaceRaised, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                .accessibilityLabel(Text("account.delete.confirm.field"))
                .accessibilityIdentifier("delete-confirm-field")
            if account.deleteFailed {
                Text("account.delete.failed").font(DSFont.footnote).foregroundStyle(DSColor.error)
            }
            Button(role: .destructive) {
                Task { await account.confirmDeletion() }
            } label: {
                HStack {
                    if account.isDeleting { ProgressView() }
                    Text("account.delete.final")
                }
                .font(DSFont.headline)
                .frame(maxWidth: .infinity, minHeight: HitTarget.button)
            }
            .buttonStyle(.borderedProminent)
            .tint(DSColor.error)
            .disabled(!account.canDelete)
            .accessibilityIdentifier("delete-final")
            SecondaryButton("common.cancel") { dismiss() }
        }
        .task { fieldFocused = true }
    }
}

import AuthenticationServices
import DataKit
import DesignSystem
import SwiftUI

enum AuthField: Hashable { case email, password }

/// Scrolling page with a title and subtitle; the keyboard is dismissed by dragging.
struct AuthScreen<Content: View>: View {
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey?
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text(title)
                        .font(DSFont.title)
                        .foregroundStyle(DSColor.textPrimary)
                        .accessibilityAddTraits(.isHeader)
                    if let subtitle {
                        Text(subtitle).font(DSFont.callout).foregroundStyle(DSColor.textSecondary)
                    }
                }
                content
            }
            .padding(Spacing.lg)
            .frame(maxWidth: 520, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .scrollBounceBehavior(.basedOnSize)
        .background(DSColor.background)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Labelled text or secure field with the DesignSystem look. The visible label is hidden from VoiceOver and
/// re-applied as the field's accessibility label, so it is read once, with the field.
struct AuthTextField: View {
    let title: LocalizedStringKey
    @Binding var text: String
    let field: AuthField
    var focus: FocusState<AuthField?>.Binding
    var isSecure = false
    var contentType: UITextContentType?
    var keyboard: UIKeyboardType = .default
    var submitLabel: SubmitLabel = .next
    var placeholder: LocalizedStringKey?
    let identifier: String
    var onSubmit: () -> Void = {}

    var body: some View {
        let isFocused = focus.wrappedValue == field
        let shape = RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(title)
                .font(DSFont.footnote)
                .foregroundStyle(DSColor.textSecondary)
                .accessibilityHidden(true)
            input
                .textContentType(contentType)
                .keyboardType(keyboard)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused(focus, equals: field)
                .submitLabel(submitLabel)
                .onSubmit(onSubmit)
                .font(DSFont.body)
                .foregroundStyle(DSColor.textPrimary)
                .padding(.horizontal, Spacing.md)
                .frame(minHeight: HitTarget.button)
                .background(DSColor.surfaceRaised, in: shape)
                .overlay(shape.strokeBorder(isFocused ? DSColor.accent : DSColor.separator, lineWidth: isFocused ? 2 : 1))
                .contentShape(shape)
                .accessibilityLabel(title)
                .accessibilityIdentifier(identifier)
        }
    }

    @ViewBuilder private var input: some View {
        let prompt = placeholder.map { Text($0).foregroundStyle(DSColor.textTertiary) }
        if isSecure {
            SecureField("", text: $text, prompt: prompt)
        } else {
            TextField("", text: $text, prompt: prompt)
        }
    }
}

/// Inline error under a form. Announced to VoiceOver when it appears.
struct AuthErrorBanner: View {
    let error: AuthError

    var body: some View {
        let message = error.errorDescription ?? ""
        HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
            Image(systemName: "exclamationmark.circle.fill").accessibilityHidden(true)
            Text(message).font(DSFont.callout).fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(DSColor.error)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.md)
        .background(DSColor.error.opacity(0.12), in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("auth.error.banner \(message)"))
        .accessibilityIdentifier("auth-error")
        .onAppear { AccessibilityNotification.Announcement(message).post() }
    }
}

/// Strength bar plus the policy checklist, shown under a new-password field.
struct PasswordStrengthView: View {
    let password: String

    var body: some View {
        let strength = PasswordStrength(password)
        let rules = PasswordRules(password)
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.sm) {
                HStack(spacing: Spacing.xs) {
                    ForEach(1...3, id: \.self) { index in
                        Capsule()
                            .fill(index <= strength.rawValue ? Self.color(for: strength) : DSColor.separator)
                            .frame(height: 4)
                    }
                }
                .accessibilityHidden(true)
                if strength != .empty {
                    Text(Self.label(for: strength)).font(DSFont.caption).foregroundStyle(Self.color(for: strength))
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Self.accessibilityLabel(for: strength))
            VStack(alignment: .leading, spacing: Spacing.xs) {
                RuleRow(title: "auth.password.rule.length", isMet: rules.hasMinimumLength)
                RuleRow(title: "auth.password.rule.lower", isMet: rules.hasLowercase)
                RuleRow(title: "auth.password.rule.upper", isMet: rules.hasUppercase)
                RuleRow(title: "auth.password.rule.digit", isMet: rules.hasDigit)
            }
        }
        .animation(.snappy(duration: 0.2), value: strength)
        .accessibilityIdentifier("auth-password-strength")
    }

    private static func color(for strength: PasswordStrength) -> Color {
        switch strength {
        case .empty, .weak: DSColor.error
        case .fair: DSColor.warning
        case .strong: DSColor.success
        }
    }

    private static func label(for strength: PasswordStrength) -> LocalizedStringKey {
        switch strength {
        case .empty, .weak: "auth.password.strength.weak"
        case .fair: "auth.password.strength.fair"
        case .strong: "auth.password.strength.strong"
        }
    }

    private static func accessibilityLabel(for strength: PasswordStrength) -> Text {
        switch strength {
        case .empty: Text("")
        case .weak: Text("auth.password.strength.accessibility.weak")
        case .fair: Text("auth.password.strength.accessibility.fair")
        case .strong: Text("auth.password.strength.accessibility.strong")
        }
    }

    private struct RuleRow: View {
        let title: LocalizedStringKey
        let isMet: Bool

        var body: some View {
            Label {
                Text(title).font(DSFont.footnote)
            } icon: {
                Image(systemName: isMet ? "checkmark.circle.fill" : "circle")
            }
            .foregroundStyle(isMet ? DSColor.success : DSColor.textSecondary)
            .accessibilityElement(children: .combine)
            .accessibilityValue(isMet ? Text("auth.password.rule.met") : Text("auth.password.rule.notMet"))
        }
    }
}

/// Native Sign in with Apple button (Apple's HIG artwork, localized by the system) that runs our own
/// `AuthService` flow instead of the SwiftUI button's built-in request.
struct AppleSignInButton: UIViewRepresentable {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isEnabled) private var isEnabled
    let action: @MainActor () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(action: action) }

    func makeUIView(context: Context) -> ASAuthorizationAppleIDButton {
        let button = ASAuthorizationAppleIDButton(type: .continue, style: colorScheme == .dark ? .white : .black)
        button.cornerRadius = Radius.md
        button.addTarget(context.coordinator, action: #selector(Coordinator.tapped), for: .touchUpInside)
        return button
    }

    func updateUIView(_ button: ASAuthorizationAppleIDButton, context: Context) {
        context.coordinator.action = action
        button.isEnabled = isEnabled
        button.alpha = isEnabled ? 1 : 0.4
    }

    final class Coordinator: NSObject {
        var action: @MainActor () -> Void
        init(action: @escaping @MainActor () -> Void) { self.action = action }
        @MainActor @objc func tapped() { action() }
    }
}

/// Terms and Privacy links. URLs come from the build configuration; a missing URL hides its link.
struct LegalLinksView: View {
    let links: LegalLinks

    var body: some View {
        VStack(spacing: Spacing.xs) {
            Text("auth.legal.intro").font(DSFont.caption).foregroundStyle(DSColor.textSecondary)
            HStack(spacing: Spacing.md) {
                if let terms = links.terms {
                    Link("auth.legal.terms", destination: terms).accessibilityIdentifier("auth-legal-terms")
                }
                if let privacy = links.privacy {
                    Link("auth.legal.privacy", destination: privacy).accessibilityIdentifier("auth-legal-privacy")
                }
            }
            .font(DSFont.caption.weight(.semibold))
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
    }
}

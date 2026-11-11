import SwiftUI

struct DSButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary }
    let kind: Kind
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
        configuration.label
            .font(DSFont.headline)
            .frame(maxWidth: .infinity, minHeight: HitTarget.button)
            .padding(.horizontal, Spacing.lg)
            .foregroundStyle(kind == .primary ? DSColor.onAccent : DSColor.textPrimary)
            .background(kind == .primary ? DSColor.accent : DSColor.surfaceRaised, in: shape)
            .overlay {
                if kind == .secondary { shape.strokeBorder(DSColor.separator, lineWidth: 1) }
            }
            .opacity(isEnabled ? 1 : 0.4)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .brightness(configuration.isPressed ? -0.05 : 0)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
            .contentShape(shape)
    }
}

private struct ButtonLabel: View {
    let title: Text
    let systemImage: String?
    var icon: Image?
    let isLoading: Bool

    var body: some View {
        HStack(spacing: Spacing.sm) {
            if isLoading {
                ProgressView().tint(.primary)
            } else if let icon {
                icon.resizable().scaledToFit().frame(width: 20, height: 20).accessibilityHidden(true)
            } else if let systemImage {
                Image(systemName: systemImage).accessibilityHidden(true)
            }
            title
        }
    }
}

/// Main call-to-action: filled with the single accent color. One per screen section.
public struct PrimaryButton: View {
    private let title: Text
    private let systemImage: String?
    private let isLoading: Bool
    private let action: @MainActor () -> Void

    public init(
        _ title: LocalizedStringKey,
        systemImage: String? = nil,
        isLoading: Bool = false,
        action: @escaping @MainActor () -> Void
    ) {
        self.title = Text(title)
        self.systemImage = systemImage
        self.isLoading = isLoading
        self.action = action
    }

    public var body: some View {
        Button {
            Haptics.play(.medium)
            action()
        } label: {
            ButtonLabel(title: title, systemImage: systemImage, isLoading: isLoading)
        }
        .buttonStyle(DSButtonStyle(kind: .primary))
        .disabled(isLoading)
    }
}

/// Secondary action: neutral raised surface with a hairline border.
public struct SecondaryButton: View {
    private let title: Text
    private let systemImage: String?
    private let icon: Image?
    private let isLoading: Bool
    private let action: @MainActor () -> Void

    public init(
        _ title: LocalizedStringKey,
        systemImage: String? = nil,
        isLoading: Bool = false,
        action: @escaping @MainActor () -> Void
    ) {
        self.init(title: Text(title), systemImage: systemImage, isLoading: isLoading, action: action)
    }

    /// With a custom (e.g. brand) icon instead of an SF Symbol; the icon is drawn as-is, not tinted.
    public init(
        _ title: LocalizedStringKey,
        icon: Image,
        isLoading: Bool = false,
        action: @escaping @MainActor () -> Void
    ) {
        self.title = Text(title)
        self.systemImage = nil
        self.icon = icon
        self.isLoading = isLoading
        self.action = action
    }

    public init(
        title: Text,
        systemImage: String?,
        isLoading: Bool = false,
        action: @escaping @MainActor () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.icon = nil
        self.isLoading = isLoading
        self.action = action
    }

    public var body: some View {
        Button {
            Haptics.play(.light)
            action()
        } label: {
            ButtonLabel(title: title, systemImage: systemImage, icon: icon, isLoading: isLoading)
        }
        .buttonStyle(DSButtonStyle(kind: .secondary))
        .disabled(isLoading)
    }
}

#Preview("Dark") { ButtonsDemo().dsPreview(.dark) }
#Preview("Light") { ButtonsDemo().dsPreview(.light) }
#Preview("Large type") { ButtonsDemo().dsPreview(.dark, type: .accessibility3) }

private struct ButtonsDemo: View {
    var body: some View {
        VStack(spacing: Spacing.md) {
            PrimaryButton("Antrenmanı Başlat", systemImage: "play.fill") {}
            PrimaryButton("Kaydediliyor", isLoading: true) {}
            SecondaryButton("Şablon Seç", systemImage: "list.bullet") {}
            PrimaryButton("Devre dışı") {}.disabled(true)
        }
    }
}

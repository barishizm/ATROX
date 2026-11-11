import SwiftUI

/// Section title with optional subtitle and trailing text action.
public struct SectionHeader: View {
    private let title: LocalizedStringKey
    private let subtitle: LocalizedStringKey?
    private let actionTitle: LocalizedStringKey?
    private let action: (@MainActor () -> Void)?

    public init(
        _ title: LocalizedStringKey,
        subtitle: LocalizedStringKey? = nil,
        actionTitle: LocalizedStringKey? = nil,
        action: (@MainActor () -> Void)? = nil
    ) {
        self.title = title
        self.subtitle = subtitle
        self.actionTitle = actionTitle
        self.action = action
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(title)
                    .font(DSFont.title)
                    .foregroundStyle(DSColor.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                if let subtitle {
                    Text(subtitle).font(DSFont.callout).foregroundStyle(DSColor.textSecondary)
                }
            }
            Spacer(minLength: Spacing.md)
            if let actionTitle, let action {
                Button {
                    Haptics.play(.selection)
                    action()
                } label: {
                    Text(actionTitle).font(DSFont.callout.weight(.semibold))
                }
                .foregroundStyle(DSColor.accent)
                .frame(minHeight: HitTarget.minimum)
            }
        }
    }
}

#Preview("Dark") { SectionHeaderDemo().dsPreview(.dark) }
#Preview("Light") { SectionHeaderDemo().dsPreview(.light) }
#Preview("Large type") { SectionHeaderDemo().dsPreview(.dark, type: .accessibility3) }

private struct SectionHeaderDemo: View {
    var body: some View {
        VStack(spacing: Spacing.lg) {
            SectionHeader("Bu Hafta")
            SectionHeader("Son Antrenmanlar", subtitle: "Son 30 gün", actionTitle: "Tümü") {}
        }
    }
}

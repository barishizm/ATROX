import SwiftUI

/// Full-width choice card: title, optional one-line description and icon, and a selection indicator.
/// `.radio` for single choice, `.checkbox` for multiple choice. Opaque, accent border when selected.
public struct SelectableCard: View {
    public enum Indicator: Sendable {
        case radio, checkbox
    }

    private let title: LocalizedStringKey
    private let subtitle: LocalizedStringKey?
    private let systemImage: String?
    private let isSelected: Bool
    private let indicator: Indicator
    private let action: () -> Void

    public init(
        _ title: LocalizedStringKey,
        subtitle: LocalizedStringKey? = nil,
        systemImage: String? = nil,
        isSelected: Bool,
        indicator: Indicator = .radio,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.isSelected = isSelected
        self.indicator = indicator
        self.action = action
    }

    private var indicatorName: String {
        switch indicator {
        case .radio: isSelected ? "checkmark.circle.fill" : "circle"
        case .checkbox: isSelected ? "checkmark.square.fill" : "square"
        }
    }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
        Button {
            Haptics.play(.selection)
            action()
        } label: {
            HStack(spacing: Spacing.md) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(DSFont.headline)
                        .foregroundStyle(isSelected ? DSColor.accent : DSColor.textSecondary)
                        .frame(width: 28)
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(title).font(DSFont.body).foregroundStyle(DSColor.textPrimary)
                    if let subtitle {
                        Text(subtitle).font(DSFont.footnote).foregroundStyle(DSColor.textSecondary)
                    }
                }
                .multilineTextAlignment(.leading)
                Spacer(minLength: Spacing.sm)
                Image(systemName: indicatorName)
                    .foregroundStyle(isSelected ? DSColor.accent : DSColor.textTertiary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .frame(maxWidth: .infinity, minHeight: HitTarget.button, alignment: .leading)
            .background(DSColor.surfaceRaised, in: shape)
            .overlay(shape.strokeBorder(isSelected ? DSColor.accent : DSColor.separator, lineWidth: isSelected ? 2 : 1))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

#Preview("Dark") { SelectableCardDemo().dsPreview(.dark) }
#Preview("Light") { SelectableCardDemo().dsPreview(.light) }
#Preview("Large type") { SelectableCardDemo().dsPreview(.dark, type: .accessibility3) }

private struct SelectableCardDemo: View {
    var body: some View {
        VStack(spacing: Spacing.sm) {
            SelectableCard(
                LocalizedStringKey("Kuvvet"), subtitle: LocalizedStringKey("Daha ağır kaldır"),
                systemImage: "bolt.fill", isSelected: true
            ) {}
            SelectableCard(
                LocalizedStringKey("Kas kazanımı"), systemImage: "figure.strengthtraining.traditional", isSelected: false
            ) {}
            SelectableCard(LocalizedStringKey("Omuz"), isSelected: true, indicator: .checkbox) {}
        }
        .padding(Spacing.md)
    }
}

import SwiftUI

/// Small status / category pill.
public struct TagChip: View {
    public enum Style: Sendable {
        case neutral, accent, success, warning, error
        case level(ScoreLevel)
    }

    private let text: LocalizedStringKey
    private let systemImage: String?
    private let style: Style

    public init(_ text: LocalizedStringKey, systemImage: String? = nil, style: Style = .neutral) {
        self.text = text
        self.systemImage = systemImage
        self.style = style
    }

    private var tint: Color {
        switch style {
        case .neutral: DSColor.textSecondary
        case .accent: DSColor.accent
        case .success: DSColor.success
        case .warning: DSColor.warning
        case .error: DSColor.error
        case .level(let l): DSColor.level(l)
        }
    }

    public var body: some View {
        HStack(spacing: Spacing.xs) {
            if let systemImage { Image(systemName: systemImage).accessibilityHidden(true) }
            Text(text)
        }
        .font(DSFont.caption.weight(.semibold))
        .foregroundStyle(tint)
        .padding(.horizontal, Spacing.sm + 2)
        .padding(.vertical, Spacing.xs + 1)
        .background(tint.opacity(TagChip.tintOpacity), in: Capsule())
    }

    /// Opacity of the tinted background; contrast of `tint` over it is asserted in tests.
    nonisolated static let tintOpacity = 0.16
}

#Preview("Dark") { TagChipDemo().dsPreview(.dark) }
#Preview("Light") { TagChipDemo().dsPreview(.light) }
#Preview("Large type") { TagChipDemo().dsPreview(.dark, type: .accessibility3) }

private struct TagChipDemo: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack { TagChip("Göğüs"); TagChip("PR", systemImage: "trophy.fill", style: .accent) }
            HStack { TagChip("Tamamlandı", style: .success); TagChip("Dikkat", style: .warning); TagChip("Hata", style: .error) }
            HStack { ForEach(ScoreLevel.allCases, id: \.self) { TagChip(LocalizedStringKey($0.localizedName), style: .level($0)) } }
        }
    }
}

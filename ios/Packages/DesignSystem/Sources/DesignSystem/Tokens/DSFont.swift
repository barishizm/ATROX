import SwiftUI

/// Typography tokens: SF Pro via system text styles, so every token scales with Dynamic Type.
/// Numbers use the rounded design with monospaced digits so values don't jitter while animating.
public enum DSFont {
    // Numerals
    public static let display = Font.system(.largeTitle, design: .rounded, weight: .heavy).monospacedDigit()
    public static let numericLarge = Font.system(.title, design: .rounded, weight: .bold).monospacedDigit()
    public static let numericMedium = Font.system(.title3, design: .rounded, weight: .semibold).monospacedDigit()
    public static let numericSmall = Font.system(.subheadline, design: .rounded, weight: .semibold).monospacedDigit()
    // Text
    public static let title = Font.system(.title2, weight: .bold)
    public static let headline = Font.system(.headline, weight: .semibold)
    public static let body = Font.system(.body)
    public static let callout = Font.system(.callout)
    public static let footnote = Font.system(.footnote)
    public static let caption = Font.system(.caption)
    /// Small uppercase label; apply `.textCase(.uppercase)` (done by `dsOverline()`).
    public static let overline = Font.system(.caption2, weight: .semibold)
}

extension View {
    /// Small tracked uppercase label in secondary text color.
    public func dsOverline() -> some View {
        font(DSFont.overline)
            .textCase(.uppercase)
            .tracking(0.8)
            .foregroundStyle(DSColor.textSecondary)
    }

    /// Liquid Glass surface. Use ONLY for navigation / floating overlay chrome
    /// (bars, floating buttons, sheets' chrome) — never for content cards.
    public func dsGlass(cornerRadius: CGFloat? = nil) -> some View {
        Group {
            if let cornerRadius {
                self.glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            } else {
                self.glassEffect(.regular, in: Capsule())
            }
        }
    }
}

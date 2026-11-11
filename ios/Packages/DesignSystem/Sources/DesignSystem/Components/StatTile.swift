import SwiftUI

/// Compact metric: caption, large rounded number, optional unit and trend.
public struct StatTile: View {
    public struct Delta: Sendable {
        public enum Direction: Sendable { case up, down, flat }
        public let text: String
        public let direction: Direction

        public init(_ text: String, direction: Direction) {
            self.text = text
            self.direction = direction
        }
    }

    private let title: LocalizedStringKey
    private let value: String
    private let unit: String?
    private let delta: Delta?

    /// `value`/`unit`/`delta` are already formatted by the caller (units & locale handled there).
    public init(_ title: LocalizedStringKey, value: String, unit: String? = nil, delta: Delta? = nil) {
        self.title = title
        self.value = value
        self.unit = unit
        self.delta = delta
    }

    public var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(title).dsOverline()
                HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
                    Text(verbatim: value)
                        .font(DSFont.numericLarge)
                        .foregroundStyle(DSColor.textPrimary)
                    if let unit {
                        Text(verbatim: unit)
                            .font(DSFont.callout)
                            .foregroundStyle(DSColor.textSecondary)
                    }
                }
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                if let delta {
                    Label(delta.text, systemImage: icon(delta.direction))
                        .font(DSFont.numericSmall)
                        .foregroundStyle(color(delta.direction))
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func icon(_ d: Delta.Direction) -> String {
        switch d {
        case .up: "arrow.up.right"
        case .down: "arrow.down.right"
        case .flat: "arrow.right"
        }
    }

    private func color(_ d: Delta.Direction) -> Color {
        switch d {
        case .up: DSColor.success
        case .down: DSColor.error
        case .flat: DSColor.textSecondary
        }
    }
}

#Preview("Dark") { StatTileDemo().dsPreview(.dark) }
#Preview("Light") { StatTileDemo().dsPreview(.light) }
#Preview("Large type") { StatTileDemo().dsPreview(.dark, type: .accessibility3) }

private struct StatTileDemo: View {
    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: Spacing.md)], spacing: Spacing.md) {
            StatTile("Hacim", value: "12.480", unit: "kg", delta: .init("+4,2%", direction: .up))
            StatTile("Seri", value: "18", delta: .init("−2", direction: .down))
            StatTile("Süre", value: "58", unit: "dk", delta: .init("0", direction: .flat))
            StatTile("Tahmini 1TM", value: "112,5", unit: "kg")
        }
    }
}

import SwiftUI

/// Content container on the `surface` layer. Opaque (no glass) — glass is reserved for chrome.
public struct Card<Content: View>: View {
    private let padding: CGFloat
    private let content: Content

    public init(padding: CGFloat = Spacing.md, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.content = content()
    }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DSColor.surface, in: shape)
            .overlay(shape.strokeBorder(DSColor.separator.opacity(0.6), lineWidth: 1))
            .dsShadow(.card)
    }
}

#Preview("Dark") { CardDemo().dsPreview(.dark) }
#Preview("Light") { CardDemo().dsPreview(.light) }
#Preview("Large type") { CardDemo().dsPreview(.dark, type: .accessibility3) }

private struct CardDemo: View {
    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("Bench Press").font(DSFont.headline).foregroundStyle(DSColor.textPrimary)
                Text("Son set: 80 kg × 8").font(DSFont.callout).foregroundStyle(DSColor.textSecondary)
            }
        }
    }
}

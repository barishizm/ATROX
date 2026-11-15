import DesignSystem
import SwiftUI

/// The mascot with a speech bubble above its head: the "guide" voice of the signed-out flow.
struct MascotSpeech: View {
    let image: String
    let message: LocalizedStringKey
    var mascotWidth: CGFloat = 200

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false
    @State private var floating = false

    var body: some View {
        VStack(spacing: 0) {
            Text(message)
                .font(DSFont.headline)
                .foregroundStyle(DSColor.textPrimary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Spacing.lg)
                .padding(.vertical, Spacing.md)
                .background(DSColor.surfaceRaised, in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
                .accessibilityAddTraits(.isHeader)
                .scaleEffect(appeared ? 1 : 0.6, anchor: .bottom)
                .opacity(appeared ? 1 : 0)
                .animation(reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.6).delay(0.2), value: appeared)
            BubbleTail()
                .fill(DSColor.surfaceRaised)
                .frame(width: 24, height: 12)
                .opacity(appeared ? 1 : 0)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.2).delay(0.25), value: appeared)
                .accessibilityHidden(true)
            Image(image)
                .resizable()
                .scaledToFit()
                .frame(width: mascotWidth)
                .padding(.top, Spacing.xs)
                // Hop in from below with a squash-and-stretch bounce, then float gently.
                .scaleEffect(x: appeared ? 1 : 0.8, y: appeared ? 1 : 0.6, anchor: .bottom)
                .offset(y: appeared ? (floating ? -6 : 0) : 60)
                .opacity(appeared ? 1 : 0)
                .animation(reduceMotion ? nil : .spring(response: 0.55, dampingFraction: 0.45), value: appeared)
                .animation(reduceMotion ? nil : .easeInOut(duration: 1.6).repeatForever(autoreverses: true), value: floating)
                .accessibilityHidden(true)
        }
        .onAppear {
            appeared = true
            if !reduceMotion {
                Task {
                    try? await Task.sleep(for: .milliseconds(700))
                    floating = true
                }
            }
        }
    }
}

/// Downward-pointing triangle that joins the bubble to the mascot.
private struct BubbleTail: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

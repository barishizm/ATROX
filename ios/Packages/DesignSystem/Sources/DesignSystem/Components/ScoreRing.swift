import SwiftUI

/// Animated 0–100 Strength Score ring. Colored by `ScoreLevel`; counts up from 0 on appear.
public struct ScoreRing: View {
    /// Clamp to 0...100 (NaN → 0).
    public nonisolated static func clamped(_ score: Double) -> Double {
        score.isFinite ? min(max(score, 0), 100) : 0
    }

    private let score: Double
    private let lineWidth: CGFloat
    private let showsLevel: Bool
    @ScaledMetric(relativeTo: .largeTitle) private var diameter: CGFloat = 160
    @State private var shown: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(score: Double, diameter: CGFloat = 160, lineWidth: CGFloat = 14, showsLevel: Bool = true) {
        self.score = Self.clamped(score)
        self.lineWidth = lineWidth
        self.showsLevel = showsLevel
        self._diameter = ScaledMetric(wrappedValue: diameter, relativeTo: .largeTitle)
    }

    private var level: ScoreLevel { ScoreLevel(score: score) }

    public var body: some View {
        let color = DSColor.level(level)
        ZStack {
            Circle().stroke(DSColor.surfaceOverlay, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: shown / 100)
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: Spacing.xxs) {
                AnimatedNumber(value: shown)
                    .font(DSFont.display)
                    .foregroundStyle(DSColor.textPrimary)
                    .lineLimit(1)
                if showsLevel {
                    Text(verbatim: level.localizedName)
                        .font(DSFont.footnote.weight(.semibold))
                        .foregroundStyle(color)
                }
            }
            .minimumScaleFactor(0.3)
            .padding(lineWidth * 1.6)
        }
        .frame(width: diameter, height: diameter)
        .padding(lineWidth / 2)
        .onAppear { update(animated: true) }
        .onChange(of: score) { update(animated: true) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("score.a11y.label", bundle: .module))
        .accessibilityValue(Text(verbatim: "\(Int(score.rounded())) / 100, \(level.localizedName)"))
    }

    private func update(animated: Bool) {
        if reduceMotion || !animated {
            shown = score
        } else {
            withAnimation(.easeOut(duration: 1.1)) { shown = score }
        }
    }
}

/// Integer label that interpolates smoothly while its value animates.
private struct AnimatedNumber: View, Animatable {
    var value: Double
    nonisolated var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    var body: some View {
        Text(verbatim: "\(Int(value.rounded()))")
    }
}

#Preview("Dark") { ScoreRingDemo().dsPreview(.dark) }
#Preview("Light") { ScoreRingDemo().dsPreview(.light) }
#Preview("Large type") { ScoreRingDemo().dsPreview(.dark, type: .accessibility3) }

private struct ScoreRingDemo: View {
    var body: some View {
        VStack(spacing: Spacing.lg) {
            ScoreRing(score: 73)
            HStack(spacing: Spacing.md) {
                ForEach([8.0, 31, 52, 73, 88, 97], id: \.self) { s in
                    ScoreRing(score: s, diameter: 44, lineWidth: 5, showsLevel: false)
                }
            }
        }
    }
}

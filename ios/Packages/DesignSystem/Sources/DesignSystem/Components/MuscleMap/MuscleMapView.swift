import SwiftUI

/// Visual options for `MuscleMapView`.
public struct MuscleMapStyle: Sendable, Equatable {
    public enum Side: Sendable, Equatable { case front, back, both }

    public var side: Side
    /// Draws the thin body silhouette behind the muscles.
    public var showsOutline: Bool
    /// Highlight color; `nil` uses the single accent color.
    public var highlight: Color?

    public init(side: Side = .both, showsOutline: Bool = true, highlight: Color? = nil) {
        self.side = side
        self.showsOutline = showsOutline
        self.highlight = highlight
    }

    public static let `default` = MuscleMapStyle()
    public static let front = MuscleMapStyle(side: .front)
    public static let back = MuscleMapStyle(side: .back)
}

/// Ready-made intensity maps for `MuscleMapView`.
public enum MuscleIntensities {
    public static let primaryLevel = 1.0
    public static let secondaryLevel = 0.45

    /// Primary muscles at full intensity, secondary at `secondaryLevel` (a muscle in both stays primary).
    public static func exercise(primary: [Muscle], secondary: [Muscle] = []) -> [Muscle: Double] {
        var result: [Muscle: Double] = [:]
        for muscle in secondary { result[muscle] = secondaryLevel }
        for muscle in primary { result[muscle] = primaryLevel }
        return result
    }

    /// Catalog strings (`"lower_back"`) -> intensities; unknown strings are ignored.
    public static func exercise(primaryNames: [String], secondaryNames: [String] = []) -> [Muscle: Double] {
        exercise(primary: primaryNames.compactMap(Muscle.init(rawValue:)),
                 secondary: secondaryNames.compactMap(Muscle.init(rawValue:)))
    }

    /// Scales arbitrary non-negative values (e.g. weekly sets or volume per muscle) so the largest becomes 1.
    public static func heatmap(_ values: [Muscle: Double]) -> [Muscle: Double] {
        let valid = values.filter { $0.value.isFinite && $0.value > 0 }
        guard let peak = valid.values.max() else { return [:] }
        return valid.mapValues { $0 / peak }
    }

    static func clamped(_ value: Double?) -> Double {
        guard let value, value.isFinite else { return 0 }
        return min(max(value, 0), 1)
    }
}

/// Front/back body map. Each muscle's 0…1 intensity is mapped onto the accent color; tapping a region reports
/// the muscle. Regions are VoiceOver elements labelled with the muscle name and value.
public struct MuscleMapView: View {
    private let intensities: [Muscle: Double]
    private let style: MuscleMapStyle
    private let onSelect: ((Muscle) -> Void)?

    @Environment(\.locale) private var locale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(intensities: [Muscle: Double], style: MuscleMapStyle = .default, onSelect: ((Muscle) -> Void)? = nil) {
        self.intensities = intensities
        self.style = style
        self.onSelect = onSelect
    }

    /// Convenience for the primary/secondary display of a single exercise.
    public init(primary: [Muscle], secondary: [Muscle] = [], style: MuscleMapStyle = .default,
                onSelect: ((Muscle) -> Void)? = nil) {
        self.init(intensities: MuscleIntensities.exercise(primary: primary, secondary: secondary),
                  style: style, onSelect: onSelect)
    }

    public var body: some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            if style.side != .back { bodyView(.front) }
            if style.side != .front { bodyView(.back) }
        }
    }

    // MARK: - Rendering

    private enum Face { case front, back }

    private func bodyView(_ face: Face) -> some View {
        let regions = face == .front ? MuscleMapGeometry.front : MuscleMapGeometry.back
        let outline = face == .front ? MuscleMapGeometry.frontOutline : MuscleMapGeometry.backOutline
        let highlight = style.highlight ?? DSColor.accent
        return ZStack {
            ForEach(regions) { region in
                regionView(region, highlight: highlight)
            }
            if style.showsOutline {
                MuscleMapShape(source: outline)
                    .stroke(DSColor.separator, style: StrokeStyle(lineWidth: 1, lineJoin: .round))
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .aspectRatio(MuscleMapGeometry.aspectRatio, contentMode: .fit)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(face == .front ? Self.frontLabel(locale) : Self.backLabel(locale)))
    }

    @ViewBuilder
    private func regionView(_ region: MuscleMapRegion, highlight: Color) -> some View {
        let shape = MuscleMapShape(source: region.path)
        if region.muscles.isEmpty {
            shape.fill(DSColor.surface)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        } else {
            let level = Self.intensity(of: region.muscles, in: intensities)
            shape
                .fill(Self.fill(level: level, highlight: highlight))
                .contentShape(shape)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: level)
                .onTapGesture { select(region) }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(Self.accessibilityLabel(for: region.muscles, locale: locale)))
                .accessibilityValue(Text(Self.accessibilityValue(for: region.muscles, intensities: intensities, locale: locale)))
                .accessibilityAddTraits(onSelect == nil ? [] : .isButton)
                .accessibilityAction { select(region) }
        }
    }

    private func select(_ region: MuscleMapRegion) {
        guard let onSelect, let muscle = Self.tappedMuscle(in: region.muscles, intensities: intensities) else { return }
        onSelect(muscle)
    }

    // MARK: - Pure helpers (unit-tested)

    /// Strongest intensity among a region's muscles (shared regions show the maximum).
    nonisolated static func intensity(of muscles: [Muscle], in intensities: [Muscle: Double]) -> Double {
        muscles.map { MuscleIntensities.clamped(intensities[$0]) }.max() ?? 0
    }

    /// Muscle reported when a region is tapped: highest intensity, ties go to the first listed muscle.
    nonisolated static func tappedMuscle(in muscles: [Muscle], intensities: [Muscle: Double]) -> Muscle? {
        var best: Muscle?
        var bestValue = -1.0
        for muscle in muscles {
            let value = MuscleIntensities.clamped(intensities[muscle])
            if value > bestValue { best = muscle; bestValue = value }
        }
        return best
    }

    nonisolated static func fill(level: Double, highlight: Color) -> Color {
        level > 0 ? DSColor.surfaceOverlay.mix(with: highlight, by: 0.2 + 0.8 * level) : DSColor.surfaceOverlay
    }

    nonisolated static func percent(_ value: Double?) -> Int { Int((MuscleIntensities.clamped(value) * 100).rounded()) }

    nonisolated static func accessibilityLabel(for muscles: [Muscle], locale: Locale) -> String {
        muscles.map { $0.localizedName(locale: locale) }.joined(separator: ", ")
    }

    /// "75%" for a single muscle, "Lats 75%, Middle back 40%" for shared regions.
    nonisolated static func accessibilityValue(for muscles: [Muscle], intensities: [Muscle: Double], locale: Locale) -> String {
        if muscles.count == 1 { return "\(percent(intensities[muscles[0]]))%" }
        return muscles.map { "\($0.localizedName(locale: locale)) \(percent(intensities[$0]))%" }.joined(separator: ", ")
    }

    private static func frontLabel(_ locale: Locale) -> String { Muscle.localized("musclemap.front", locale: locale) ?? "Front" }
    private static func backLabel(_ locale: Locale) -> String { Muscle.localized("musclemap.back", locale: locale) ?? "Back" }
}

#Preview("Both") {
    MuscleMapView(primary: [.chest, .triceps], secondary: [.shoulders]).padding().background(DSColor.background)
}

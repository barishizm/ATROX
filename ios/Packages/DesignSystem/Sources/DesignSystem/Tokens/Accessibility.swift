import Accessibility
import SwiftUI

// MARK: - Motion

private struct MotionAdaptiveModifier<V: Equatable>: ViewModifier {
    let animation: Animation?
    let value: V
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? nil : animation, value: value)
    }
}

extension View {
    /// Like `.animation(_:value:)`, but state changes apply instantly when Reduce Motion is on.
    public func dsAnimation<V: Equatable>(_ animation: Animation? = .snappy, value: V) -> some View {
        modifier(MotionAdaptiveModifier(animation: animation, value: value))
    }

    /// Replaces a scale/slide transition with a plain fade when Reduce Motion is on.
    public func dsTransition(_ transition: AnyTransition) -> some View {
        modifier(MotionTransitionModifier(transition: transition))
    }

    /// Guarantees the HIG minimum touch target without changing the visual size.
    public func dsMinimumHitTarget() -> some View {
        frame(minWidth: HitTarget.minimum, minHeight: HitTarget.minimum).contentShape(Rectangle())
    }
}

private struct MotionTransitionModifier: ViewModifier {
    let transition: AnyTransition
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.transition(reduceMotion ? .opacity : transition)
    }
}

// MARK: - Chart descriptor

/// One data point of a time series for VoiceOver's Audio Graph.
public struct ChartSeriesPoint: Sendable, Equatable {
    public let date: Date
    public let value: Double

    public init(date: Date, value: Double) {
        self.date = date
        self.value = value
    }
}

/// Describes a single-series date/value chart to VoiceOver (`AXChartDescriptor`): the Audio Graph plays the line and
/// the summary is read first. Charts keep their visual look; this only supplies the accessible representation.
public struct SeriesChartDescriptor: AXChartDescriptorRepresentable {
    public let title: String
    public let summary: String
    public let xTitle: String
    public let yTitle: String
    public let unit: String?
    public let points: [ChartSeriesPoint]
    public let locale: Locale

    public init(
        title: String, summary: String, xTitle: String, yTitle: String, unit: String? = nil,
        points: [ChartSeriesPoint], locale: Locale = .current
    ) {
        self.title = title
        self.summary = summary
        self.xTitle = xTitle
        self.yTitle = yTitle
        self.unit = unit
        self.points = points
        self.locale = locale
    }

    /// Y axis range, widened when all values are equal so the axis is never degenerate. Pure, for tests.
    public nonisolated static func range(of values: [Double]) -> ClosedRange<Double> {
        guard let low = values.min(), let high = values.max() else { return 0...1 }
        return low == high ? (low - 1)...(high + 1) : low...high
    }

    public func makeChartDescriptor() -> AXChartDescriptor {
        let dates = points.map(\.date.timeIntervalSinceReferenceDate)
        let xRange = Self.range(of: dates)
        let formatter = Date.FormatStyle(date: .abbreviated, time: .omitted).locale(locale)
        let xAxis = AXNumericDataAxisDescriptor(
            title: xTitle, range: xRange, gridlinePositions: []
        ) { Date(timeIntervalSinceReferenceDate: $0).formatted(formatter) }
        let yRange = Self.range(of: points.map(\.value))
        let suffix = unit.map { " \($0)" } ?? ""
        let yAxis = AXNumericDataAxisDescriptor(
            title: yTitle, range: yRange, gridlinePositions: []
        ) { $0.formatted(.number.precision(.fractionLength(0...1)).locale(locale)) + suffix }
        let series = AXDataSeriesDescriptor(
            name: title, isContinuous: true,
            dataPoints: points.map { AXDataPoint(x: $0.date.timeIntervalSinceReferenceDate, y: $0.value) }
        )
        return AXChartDescriptor(
            title: title, summary: summary, xAxis: xAxis, yAxis: yAxis, additionalAxes: [], series: [series]
        )
    }
}

extension View {
    /// Attaches a VoiceOver Audio Graph description to a chart.
    public func dsChartDescriptor(_ descriptor: SeriesChartDescriptor) -> some View {
        accessibilityChartDescriptor(descriptor)
    }
}

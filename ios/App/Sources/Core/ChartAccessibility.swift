import DesignSystem
import Foundation

/// Builds the VoiceOver Audio Graph descriptors for the app's time-series charts (P097).
enum ChartAccessibility {
    /// Spoken summary: point count, first/latest/lowest/highest value. Pure for tests.
    static func summary(values: [Double], unit: String?, locale: Locale) -> String {
        guard let first = values.first, let last = values.last, let low = values.min(), let high = values.max() else {
            return String(localized: "a11y.chart.empty", locale: locale)
        }
        let suffix = unit.map { " \($0)" } ?? ""
        func text(_ v: Double) -> String { v.formatted(.number.precision(.fractionLength(0...1)).locale(locale)) + suffix }
        let template = String(localized: "a11y.chart.summary", locale: locale)
        return String(format: template, locale: locale, values.count, text(first), text(last), text(low), text(high))
    }

    static func descriptor(
        title: String, points: [ChartSeriesPoint], yTitle: String, unit: String? = nil, locale: Locale
    ) -> SeriesChartDescriptor {
        SeriesChartDescriptor(
            title: title,
            summary: summary(values: points.map(\.value), unit: unit, locale: locale),
            xTitle: String(localized: "a11y.chart.date", locale: locale),
            yTitle: yTitle, unit: unit, points: points, locale: locale
        )
    }
}

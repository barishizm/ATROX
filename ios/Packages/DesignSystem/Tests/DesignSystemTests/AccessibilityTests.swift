@testable import DesignSystem
import Foundation
import Testing

@Suite struct AccessibilityTests {
    @Test func rangeWidensDegenerateSeries() {
        #expect(SeriesChartDescriptor.range(of: [5, 5, 5]) == 4...6)
        #expect(SeriesChartDescriptor.range(of: [3, 9, 1]) == 1...9)
        #expect(SeriesChartDescriptor.range(of: []) == 0...1)
    }

    @Test func descriptorCarriesAllPoints() {
        let start = Date(timeIntervalSinceReferenceDate: 0)
        let points = (0..<4).map { ChartSeriesPoint(date: start.addingTimeInterval(Double($0) * 86_400), value: Double($0) * 10) }
        let descriptor = SeriesChartDescriptor(
            title: "Weight", summary: "four points", xTitle: "Date", yTitle: "Weight", unit: "kg",
            points: points, locale: Locale(identifier: "en_US")
        ).makeChartDescriptor()
        #expect(descriptor.series.first?.dataPoints.count == 4)
        #expect(descriptor.summary == "four points")
    }
}

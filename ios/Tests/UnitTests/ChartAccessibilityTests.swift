@testable import ATROX
import DesignSystem
import Foundation
import Testing

@Suite struct ChartAccessibilityTests {
    private let en = Locale(identifier: "en_US")

    @Test func summaryNamesCountFirstLastLowHigh() {
        let text = ChartAccessibility.summary(values: [80, 82.5, 79, 85], unit: "kg", locale: en)
        #expect(text.contains("4"))
        #expect(text.contains("80 kg"))
        #expect(text.contains("85 kg"))
        #expect(text.contains("79 kg"))
    }

    @Test func emptySeriesHasSpokenFallback() {
        #expect(!ChartAccessibility.summary(values: [], unit: nil, locale: en).isEmpty)
    }

    @Test func descriptorKeepsEveryPoint() {
        let points = (0..<3).map { ChartSeriesPoint(date: Date(timeIntervalSinceReferenceDate: Double($0) * 86_400), value: Double($0)) }
        let descriptor = ChartAccessibility.descriptor(title: "T", points: points, yTitle: "Y", locale: en)
        #expect(descriptor.points.count == 3)
        #expect(descriptor.unit == nil)
    }
}

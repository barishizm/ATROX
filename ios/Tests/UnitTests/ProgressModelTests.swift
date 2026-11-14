import DataKit
import Foundation
import StrengthKit
import Testing

@testable import ATROX

@Suite struct ProgressModelTests {
    @Test func paceBandsAroundTheExpectedScore() {
        #expect(ProgressModel.pace(value: 75) == .faster)
        #expect(ProgressModel.pace(value: 60) == .faster)
        #expect(ProgressModel.pace(value: 50) == .onTrack)
        #expect(ProgressModel.pace(value: 41) == .onTrack)
        #expect(ProgressModel.pace(value: 40) == .slower)
        #expect(ProgressModel.pace(value: 12) == .slower)
        #expect(ProgressModel.pace(value: nil) == .unknown)
    }

    @Test func percentTextIsSignedAndLocaleAware() {
        #expect(ProgressModel.percentText(0.0234, locale: Locale(identifier: "en")) == "+2.3 %")
        #expect(ProgressModel.percentText(0.0234, locale: Locale(identifier: "tr")) == "+2,3 %")
        #expect(ProgressModel.percentText(-0.01, locale: Locale(identifier: "en")) == "−1 %")
    }

    @Test func volumeWeeksGrowWithTheRange() {
        let weeks = ChartRange.allCases.map(ProgressModel.volumeWeeks)
        #expect(weeks == weeks.sorted() && weeks.first == 5 && weeks.last == 104)
    }

    @Test func nearestPicksTheClosestPointInTime() {
        struct Item { let date: Date }
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        let items = [0, 10, 20].map { Item(date: base.addingTimeInterval(Double($0) * 86_400)) }
        #expect(ProgressModel.nearest(items, to: base.addingTimeInterval(8 * 86_400), at: \.date)?.date == items[1].date)
        #expect(ProgressModel.nearest(items, to: base.addingTimeInterval(-50 * 86_400), at: \.date)?.date == items[0].date)
        #expect(ProgressModel.nearest([Item](), to: base, at: \.date) == nil)
    }
}

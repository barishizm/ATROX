import XCTest

/// Cold-launch measurement (P098). Runs on CI; the target is first frame < 1 s on a mid-range device
/// (`docs/PERFORMANS.md`). The simulator is faster than a device, so the budget below only guards regressions.
final class PerformanceUITests: XCTestCase {
    @MainActor
    func testColdLaunchStaysUnderBudget() throws {
        var options = XCTMeasureOptions()
        options.iterationCount = 3
        let started = Date()
        measure(metrics: [XCTApplicationLaunchMetric()], options: options) {
            XCUIApplication().launch()
        }
        // Each iteration includes terminate + launch; three of them must stay far below any hang threshold.
        XCTAssertLessThan(Date().timeIntervalSince(started), 60)
    }
}

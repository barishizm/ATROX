@testable import ATROX
import DataKit
import Foundation
import Testing

@Suite("Analytics app wiring (P100)")
struct AnalyticsAppTests {
    @Test func userDefaultsStorageRoundTripsAndStaysOffUntilSet() {
        let suite = UserDefaults(suiteName: "analytics-\(UUID().uuidString)")!
        let storage = UserDefaultsAnalyticsStorage(defaults: suite)
        #expect(storage.bool(forKey: AnalyticsService.enabledKey) == nil)
        let service = AnalyticsService(sink: RecordingAnalytics(), storage: storage)
        #expect(service.isEnabled)
        suite.set(false, forKey: AnalyticsService.enabledKey)
        #expect(!service.isEnabled)
    }

    @Test func diagnosticsSummaryHasCountsOnly() {
        #expect(DiagnosticsCollector.summary(crashes: 1, hangs: 2, cpuExceptions: 0, diskWrites: 3) == "crashes=1 hangs=2 cpu=0 diskWrites=3")
    }
}

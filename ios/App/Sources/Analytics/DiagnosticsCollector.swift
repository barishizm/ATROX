import Foundation
import MetricKit
import OSLog

/// Collects MetricKit crash, hang, CPU and disk-write diagnostics and logs an anonymous summary (P100).
/// Only counts and categories are logged: no call-stack text with user data, no identifiers. Delivery is once a day
/// (metrics) and after the next launch (diagnostics), so nothing here runs on a hot path.
final class DiagnosticsCollector: NSObject, MXMetricManagerSubscriber, @unchecked Sendable {
    static let shared = DiagnosticsCollector()
    private let log = Logger(subsystem: "com.barishizm.atrox", category: "diagnostics")

    func start() { MXMetricManager.shared.add(self) }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for payload in payloads {
            let summary = Self.summary(
                crashes: payload.crashDiagnostics?.count ?? 0, hangs: payload.hangDiagnostics?.count ?? 0,
                cpuExceptions: payload.cpuExceptionDiagnostics?.count ?? 0, diskWrites: payload.diskWriteExceptionDiagnostics?.count ?? 0
            )
            log.error("MetricKit diagnostics: \(summary, privacy: .public)")
        }
    }

    func didReceive(_ payloads: [MXMetricPayload]) {
        for payload in payloads {
            let launch = payload.applicationLaunchMetrics?.histogrammedTimeToFirstDraw.totalBucketCount ?? 0
            let exits = payload.applicationExitMetrics?.foregroundExitData.cumulativeAbnormalExitCount ?? 0
            log.info("MetricKit metrics: launches=\(launch, privacy: .public) abnormalForegroundExits=\(exits, privacy: .public)")
        }
    }

    /// Pure formatting, unit-tested.
    static func summary(crashes: Int, hangs: Int, cpuExceptions: Int, diskWrites: Int) -> String {
        "crashes=\(crashes) hangs=\(hangs) cpu=\(cpuExceptions) diskWrites=\(diskWrites)"
    }
}

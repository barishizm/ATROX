import Foundation
import Network

/// "Is there a network?" as a stream, from `NWPathMonitor` (P045: sync when the network comes back).
public enum NetworkPathMonitor {
    /// Yields the current state first, then every change. The monitor stops when the stream is cancelled.
    public static func updates() -> AsyncStream<Bool> {
        AsyncStream { continuation in
            let monitor = NWPathMonitor()
            monitor.pathUpdateHandler = { path in continuation.yield(path.status == .satisfied) }
            continuation.onTermination = { _ in monitor.cancel() }
            monitor.start(queue: DispatchQueue(label: "com.barishizm.atrox.network-monitor"))
        }
    }
}

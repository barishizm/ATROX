@testable import DataKit
import Foundation

/// Controllable clock so tests can assert exact `updatedAt` values.
final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date

    init(_ start: Date = Date(timeIntervalSince1970: 1_800_000_000)) { current = start }

    var now: Date { lock.withLock { current } }

    func advance(by seconds: TimeInterval) { lock.withLock { current = current.addingTimeInterval(seconds) } }

    var closure: @Sendable () -> Date { { [self] in now } }
}

let testUser = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
let otherUser = UUID(uuidString: "22222222-2222-4222-8222-222222222222")!

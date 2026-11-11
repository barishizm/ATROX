import Foundation
import Testing
@testable import DataKit

@Suite struct SyncStateTests {
    @Test func rawValuesMatchBackendContract() {
        #expect(SyncState.allCases.map(\.rawValue) == ["synced", "pending", "failed"])
    }

    @Test func codableRoundTrip() throws {
        let data = try JSONEncoder().encode(SyncState.pending)
        #expect(try JSONDecoder().decode(SyncState.self, from: data) == .pending)
    }
}

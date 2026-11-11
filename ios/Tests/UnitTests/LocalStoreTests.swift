import DataKit
import Foundation
import SwiftData
import Testing

@testable import GymAnalyzer

struct LocalStoreTests {
    @Test func appGroupIDDerivesFromBundleID() throws {
        let group = try #require(Bundle.main.infoDictionary?["AppGroupID"] as? String)
        #expect(group.hasPrefix("group.com.barishizm.vesania"))
    }

    @Test func appGroupContainerOpensAndPersists() async throws {
        let group = try #require(Bundle.main.infoDictionary?["AppGroupID"] as? String)
        // Simulator builds carry the app-group entitlement, so the shared container must resolve.
        let container = try DataStore.production(appGroupID: group)
        let userId = UUID()
        let repo = SwiftDataProfileRepository(modelContainer: container)
        try await repo.upsert(DataFixtures.profileInput(), userId: userId)
        #expect(try await repo.profile(userId: userId) != nil)
        try await repo.delete(userId: userId)
    }
}

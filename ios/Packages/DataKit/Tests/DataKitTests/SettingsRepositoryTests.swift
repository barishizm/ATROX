@testable import DataKit
import Foundation
import SwiftData
import Testing

@Suite struct SettingsRepositoryTests {
    private let clock = TestClock()

    private func makeRepo() throws -> SwiftDataSettingsRepository {
        SwiftDataSettingsRepository(modelContainer: try DataStore.inMemory(), clock: clock.closure)
    }

    @Test func firstReadCreatesDefaultsOnce() async throws {
        let repo = try makeRepo()
        let first = try await repo.settings(userId: testUser)
        #expect(first.input == SettingsInput())
        #expect(first.syncState == .pending)
        let again = try await repo.settings(userId: testUser)
        #expect(again.id == first.id)
    }

    @Test func updatePersistsAndBumpsUpdatedAt() async throws {
        let repo = try makeRepo()
        let created = try await repo.settings(userId: testUser)
        clock.advance(by: 60)
        var input = created.input
        input.theme = .light
        input.weightUnit = .lb
        input.lengthUnit = .inch
        let saved = try await repo.update(input, userId: testUser)
        #expect(saved.id == created.id)
        #expect(saved.updatedAt == clock.now)
        #expect(try await repo.settings(userId: testUser).input == input)
    }

    @Test func updateCreatesRowWhenMissing() async throws {
        let repo = try makeRepo()
        let saved = try await repo.update(SettingsInput(theme: .dark), userId: testUser)
        #expect(saved.input.theme == .dark)
    }

    @Test func settingsAreScopedToUser() async throws {
        let repo = try makeRepo()
        try await repo.update(SettingsInput(theme: .dark), userId: testUser)
        #expect(try await repo.settings(userId: otherUser).input.theme == .system)
    }

    @Test func invalidValuesAreRejected() async throws {
        let repo = try makeRepo()
        await #expect(throws: DataError.invalidValue("restTimerSeconds")) {
            try await repo.update(SettingsInput(restTimerSeconds: 0), userId: testUser)
        }
        await #expect(throws: DataError.invalidValue("defaultBarKg")) {
            try await repo.update(SettingsInput(defaultBarKg: -1), userId: testUser)
        }
    }
}

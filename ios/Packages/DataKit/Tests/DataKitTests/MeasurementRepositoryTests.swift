@testable import DataKit
import Foundation
import SwiftData
import Testing

@Suite struct MeasurementRepositoryTests {
    private let clock = TestClock()

    private func makeRepo() throws -> SwiftDataMeasurementRepository {
        SwiftDataMeasurementRepository(modelContainer: try DataStore.inMemory(), clock: clock.closure)
    }

    private func day(_ offset: Int) -> Date { clock.now.addingTimeInterval(Double(offset) * 86_400) }

    @Test func addStoresPendingRow() async throws {
        let repo = try makeRepo()
        let saved = try await repo.add(MeasurementInput(date: day(0), weightKg: 80.5, bodyFatPct: 14.2), userId: testUser)
        #expect(saved.syncState == .pending)
        #expect(saved.updatedAt == clock.now)
        #expect(saved.input.weightKg == 80.5)
        #expect(saved.input.bodyFatPct == 14.2)
        #expect(saved.input.source == .manual)
    }

    @Test func allIsNewestFirstAndScopedToUser() async throws {
        let repo = try makeRepo()
        try await repo.add(MeasurementInput(date: day(-14), weightKg: 79), userId: testUser)
        try await repo.add(MeasurementInput(date: day(0), weightKg: 81), userId: testUser)
        try await repo.add(MeasurementInput(date: day(-7), weightKg: 80), userId: testUser)
        try await repo.add(MeasurementInput(date: day(0), weightKg: 99), userId: otherUser)
        let weights = try await repo.all(userId: testUser).map(\.input.weightKg)
        #expect(weights == [81, 80, 79])
        #expect(try await repo.latest(userId: testUser)?.input.weightKg == 81)
        #expect(try await repo.latest(userId: UUID()) == nil)
    }

    @Test func updateChangesValuesAndBumpsUpdatedAt() async throws {
        let repo = try makeRepo()
        let saved = try await repo.add(MeasurementInput(date: day(0), weightKg: 80), userId: testUser)
        clock.advance(by: 30)
        let updated = try await repo.update(id: saved.id, with: MeasurementInput(date: day(0), weightKg: 79.4, source: .healthkit))
        #expect(updated.id == saved.id)
        #expect(updated.input.weightKg == 79.4)
        #expect(updated.input.source == .healthkit)
        #expect(updated.updatedAt == clock.now)
        #expect(updated.createdAt == saved.createdAt)
    }

    @Test func deleteIsSoftAndHidesRow() async throws {
        let container = try DataStore.inMemory()
        let repo = SwiftDataMeasurementRepository(modelContainer: container, clock: clock.closure)
        let saved = try await repo.add(MeasurementInput(date: day(0), weightKg: 80), userId: testUser)
        clock.advance(by: 1)
        try await repo.delete(id: saved.id)
        #expect(try await repo.all(userId: testUser).isEmpty)
        let rows = try ModelContext(container).fetch(FetchDescriptor<BodyMeasurement>())
        #expect(rows.count == 1)
        #expect(rows.first?.deletedAt == clock.now)
        #expect(rows.first?.syncState == .pending)
        await #expect(throws: DataError.notFound) { try await repo.delete(id: saved.id) }
        await #expect(throws: DataError.notFound) {
            try await repo.update(id: saved.id, with: MeasurementInput(date: day(0), weightKg: 80))
        }
    }

    @Test func rejectsOutOfRangeValues() async throws {
        let repo = try makeRepo()
        await #expect(throws: DataError.invalidValue("weightKg")) {
            try await repo.add(MeasurementInput(date: day(0), weightKg: 19.9), userId: testUser)
        }
        await #expect(throws: DataError.invalidValue("bodyFatPct")) {
            try await repo.add(MeasurementInput(date: day(0), weightKg: 80, bodyFatPct: 71), userId: testUser)
        }
        #expect(try await repo.all(userId: testUser).isEmpty)
    }
}

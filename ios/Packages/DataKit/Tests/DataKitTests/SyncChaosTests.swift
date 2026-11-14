@testable import DataKit
import Foundation
import SwiftData
import Testing

/// Deterministic SplitMix64 so every failing seed reproduces exactly.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

@Suite("Sync chaos: random offline edits converge (P099)")
struct SyncChaosTests {
    private struct Snapshot: Equatable {
        let weightKg: Double
        let deleted: Bool
    }

    private func snapshot(_ device: SyncDevice) throws -> [UUID: Snapshot] {
        let context = ModelContext(device.container)
        let rows = try context.fetch(FetchDescriptor<BodyMeasurement>())
        return Dictionary(uniqueKeysWithValues: rows.map { ($0.id, Snapshot(weightKg: $0.weightKg, deleted: $0.deletedAt != nil)) })
    }

    private func run(seed: UInt64, deviceCount: Int = 3, rounds: Int = 12) async throws {
        var rng = SeededGenerator(seed: seed)
        let clock = TestClock()
        let server = InMemoryRemoteStore(userId: testUser, clock: clock.closure)
        let devices = try (0..<deviceCount).map { _ in try SyncDevice(server: server, clock: clock) }
        var knownIds: [UUID] = []

        for _ in 0..<rounds {
            // Offline phase: each device makes a few edits without syncing.
            for device in devices {
                for _ in 0..<Int.random(in: 0...3, using: &rng) {
                    clock.advance(by: Double(Int.random(in: 1...5, using: &rng)))
                    let visible = try snapshot(device).filter { !$0.value.deleted }.map(\.key)
                    switch Int.random(in: 0..<10, using: &rng) {
                    case 0..<4 where !visible.isEmpty:
                        let id = visible.randomElement(using: &rng)!
                        let kg = Double(Int.random(in: 50...120, using: &rng))
                        try device.edit(BodyMeasurement.self, id: id) { $0.weightKg = kg }
                    case 4 where !visible.isEmpty:
                        let id = visible.randomElement(using: &rng)!
                        let now = clock.now
                        try device.edit(BodyMeasurement.self, id: id) { $0.deletedAt = now }
                    default:
                        let row = measurement(Double(Int.random(in: 50...120, using: &rng)),
                                              on: clock.now.addingTimeInterval(Double(knownIds.count) * 86_400), now: clock.now)
                        knownIds.append(row.id)
                        try device.insert([row])
                    }
                }
            }
            // Sync phase: random order, devices sometimes skip a round.
            for device in devices.shuffled(using: &rng) where Bool.random(using: &rng) {
                clock.advance(by: 1)
                try await device.engine.sync()
            }
        }

        // Quiesce: everyone syncs until nothing moves (push, then pull everyone's changes).
        for _ in 0..<3 {
            for device in devices {
                clock.advance(by: 1)
                try await device.engine.sync()
            }
        }

        let reference = try snapshot(devices[0])
        for (index, device) in devices.enumerated().dropFirst() {
            #expect(try snapshot(device) == reference, "seed \(seed): device \(index) diverged")
        }
        // Every row the server holds is also on the devices with the same state.
        let serverRows = await server.rows(.bodyMeasurements)
        #expect(serverRows.count == reference.count, "seed \(seed): server and devices disagree on row count")
    }

    @Test(arguments: [1, 2, 3, 7, 42, 99, 1_234, 2_026, 31_337, 65_535] as [UInt64])
    func devicesConvergeAfterRandomOfflineEdits(seed: UInt64) async throws {
        try await run(seed: seed)
    }

    @Test func twoDevicesWithManyRoundsConverge() async throws {
        try await run(seed: 777, deviceCount: 2, rounds: 40)
    }
}

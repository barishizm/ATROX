import DataKit
import Foundation
import HealthKit

/// Real Apple Health access. Reads: height, body mass, date of birth, biological sex.
/// Writes: body mass and workouts (strength training, P041).
final class HealthKitService: HealthService, @unchecked Sendable {
    // HKHealthStore is thread-safe; the type itself is not marked Sendable.
    private let store = HKHealthStore()

    private static let height = HKQuantityType(.height)
    private static let bodyMass = HKQuantityType(.bodyMass)
    private static let kilogram = HKUnit.gramUnit(with: .kilo)

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    func requestAuthorization() async -> Bool {
        guard isAvailable else { return false }
        let read: Set<HKObjectType> = [
            Self.height, Self.bodyMass,
            HKCharacteristicType(.dateOfBirth), HKCharacteristicType(.biologicalSex)
        ]
        let share: Set<HKSampleType> = [Self.bodyMass, HKObjectType.workoutType()]
        do {
            try await store.requestAuthorization(toShare: share, read: read)
            return true
        } catch {
            Log.app.error("Health authorization failed: \(error)")
            return false
        }
    }

    func canWriteWeight() async -> Bool {
        isAvailable && store.authorizationStatus(for: Self.bodyMass) == .sharingAuthorized
    }

    func bodyProfile() async -> HealthBodyProfile {
        guard isAvailable else { return HealthBodyProfile() }
        async let height = latestValue(of: Self.height, unit: .meterUnit(with: .centi))
        async let weight = latestValue(of: Self.bodyMass, unit: Self.kilogram)
        let birthDate = (try? store.dateOfBirthComponents()).flatMap { Calendar(identifier: .gregorian).date(from: $0) }
        let sex: Sex? = switch (try? store.biologicalSex())?.biologicalSex {
        case .male: .male
        case .female: .female
        default: nil
        }
        return await HealthBodyProfile(heightCm: height, weightKg: weight, birthDate: birthDate, sex: sex)
    }

    func weightSamples(since: Date) async -> [HealthWeightSample] {
        guard isAvailable else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: since, end: nil)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: Self.bodyMass, predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.endDate, order: .reverse)],
            limit: 500
        )
        do {
            return try await descriptor.result(for: store).map {
                HealthWeightSample(
                    date: $0.endDate, weightKg: $0.quantity.doubleValue(for: Self.kilogram),
                    isFromThisApp: $0.sourceRevision.source == HKSource.default()
                )
            }
        } catch {
            Log.app.error("Health weight query failed: \(error)")
            return []
        }
    }

    func saveWeight(kilograms: Double, date: Date) async -> Bool {
        guard await canWriteWeight() else { return false }
        let sample = HKQuantitySample(
            type: Self.bodyMass, quantity: HKQuantity(unit: Self.kilogram, doubleValue: kilograms), start: date, end: date
        )
        do {
            try await store.save(sample)
            return true
        } catch {
            Log.app.error("Health weight save failed: \(error)")
            return false
        }
    }

    func saveWorkout(id: UUID, start: Date, end: Date) async -> UUID? {
        guard isAvailable, store.authorizationStatus(for: HKObjectType.workoutType()) == .sharingAuthorized else { return nil }
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .traditionalStrengthTraining
        configuration.locationType = .indoor
        let builder = HKWorkoutBuilder(healthStore: store, configuration: configuration, device: .local())
        do {
            try await builder.beginCollection(at: start)
            // The sync identifier makes Health treat a second write of the same workout as the same record.
            try await builder.addMetadata([HKMetadataKeySyncIdentifier: id.uuidString, HKMetadataKeySyncVersion: 1])
            try await builder.endCollection(at: max(end, start))
            return try await builder.finishWorkout()?.uuid
        } catch {
            Log.app.error("Health workout save failed: \(error)")
            return nil
        }
    }

    func deleteWorkout(uuid: UUID) async -> Bool {
        guard isAvailable else { return false }
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.workout(HKQuery.predicateForObject(with: uuid))], sortDescriptors: [], limit: 1
        )
        do {
            guard let workout = try await descriptor.result(for: store).first else { return true }
            try await store.delete(workout)
            return true
        } catch {
            Log.app.error("Health workout delete failed: \(error)")
            return false
        }
    }

    private func latestValue(of type: HKQuantityType, unit: HKUnit) async -> Double? {
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: type)],
            sortDescriptors: [SortDescriptor(\.endDate, order: .reverse)],
            limit: 1
        )
        let sample = try? await descriptor.result(for: store).first
        return sample?.quantity.doubleValue(for: unit)
    }
}

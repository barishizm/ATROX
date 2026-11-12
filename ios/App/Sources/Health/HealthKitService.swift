import DataKit
import Foundation
import HealthKit

/// Real Apple Health access. Reads: height, body mass, date of birth, biological sex.
/// Writes: body mass and workouts (workout saving itself arrives with P041).
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

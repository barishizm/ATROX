import Foundation

/// Value types that cross the actor boundary (SwiftData models are not `Sendable`).

public enum DataError: Error, Equatable, Sendable {
    case notFound
    case invalidValue(String)
}

public struct ProfileInput: Sendable, Equatable {
    public var firstName: String?
    public var lastName: String?
    public var birthDate: Date
    public var sex: Sex
    public var heightCm: Double
    public var unitSystem: UnitSystem
    public var experience: Experience
    public var goal: Goal
    public var weeklyFrequency: Int
    public var equipmentAccess: EquipmentAccess
    public var limitations: [String]
    public var locale: String

    public init(
        firstName: String?, lastName: String? = nil, birthDate: Date, sex: Sex = .unspecified,
        heightCm: Double, unitSystem: UnitSystem = .metric, experience: Experience = .noExperience,
        goal: Goal = .generalHealth, weeklyFrequency: Int = 3, equipmentAccess: EquipmentAccess = .fullGym,
        limitations: [String] = [], locale: String = "en"
    ) {
        self.firstName = firstName
        self.lastName = lastName
        self.birthDate = birthDate
        self.sex = sex
        self.heightCm = heightCm
        self.unitSystem = unitSystem
        self.experience = experience
        self.goal = goal
        self.weeklyFrequency = weeklyFrequency
        self.equipmentAccess = equipmentAccess
        self.limitations = limitations
        self.locale = locale
    }
}

public struct MeasurementInput: Sendable, Equatable {
    public var date: Date
    public var weightKg: Double
    public var bodyFatPct: Double?
    public var source: MeasurementSource

    public init(date: Date, weightKg: Double, bodyFatPct: Double? = nil, source: MeasurementSource = .manual) {
        self.date = date
        self.weightKg = weightKg
        self.bodyFatPct = bodyFatPct
        self.source = source
    }
}

public struct ProfileSnapshot: Sendable, Equatable, Identifiable {
    public let id: UUID
    public let userId: UUID
    public let createdAt: Date
    public let updatedAt: Date
    public let deletedAt: Date?
    public let syncState: SyncState
    public let input: ProfileInput
}

public struct MeasurementSnapshot: Sendable, Equatable, Identifiable {
    public let id: UUID
    public let userId: UUID
    public let createdAt: Date
    public let updatedAt: Date
    public let deletedAt: Date?
    public let syncState: SyncState
    public let input: MeasurementInput
}

public struct ConsentSnapshot: Sendable, Equatable, Identifiable {
    public let id: UUID
    public let userId: UUID
    public let createdAt: Date
    public let syncState: SyncState
    public let kind: ConsentKind
    public let version: String
    public let granted: Bool
}

// MARK: - Model → snapshot

extension UserProfile {
    var snapshot: ProfileSnapshot {
        ProfileSnapshot(
            id: id, userId: userId, createdAt: createdAt, updatedAt: updatedAt, deletedAt: deletedAt,
            syncState: syncState,
            input: ProfileInput(
                firstName: firstName, lastName: lastName, birthDate: birthDate, sex: sex, heightCm: heightCm,
                unitSystem: unitSystem, experience: experience, goal: goal, weeklyFrequency: weeklyFrequency,
                equipmentAccess: equipmentAccess, limitations: limitations, locale: locale
            )
        )
    }
}

extension BodyMeasurement {
    var snapshot: MeasurementSnapshot {
        MeasurementSnapshot(
            id: id, userId: userId, createdAt: createdAt, updatedAt: updatedAt, deletedAt: deletedAt,
            syncState: syncState,
            input: MeasurementInput(date: date, weightKg: weightKg, bodyFatPct: bodyFatPct, source: source)
        )
    }
}

extension ConsentRecord {
    var snapshot: ConsentSnapshot {
        ConsentSnapshot(
            id: id, userId: userId, createdAt: createdAt, syncState: syncState,
            kind: kind, version: version, granted: granted
        )
    }
}

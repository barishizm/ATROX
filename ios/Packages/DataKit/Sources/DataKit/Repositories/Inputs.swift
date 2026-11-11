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

    /// Public so previews and tests in other modules can build snapshots without a store.
    public init(
        id: UUID = UUID(), userId: UUID, createdAt: Date = Date(), updatedAt: Date? = nil, deletedAt: Date? = nil,
        syncState: SyncState = .pending, input: MeasurementInput
    ) {
        self.id = id
        self.userId = userId
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
        self.deletedAt = deletedAt
        self.syncState = syncState
        self.input = input
    }
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

public struct SettingsInput: Sendable, Equatable {
    public var theme: ThemePreference
    public var weightUnit: WeightUnit
    public var lengthUnit: LengthUnit
    public var referenceGroup: ReferenceGroup
    public var rirEnabled: Bool
    public var restTimerSeconds: Int
    public var defaultBarKg: Double
    /// Plates are stored in kg like every other weight.
    public var availablePlatesKg: [Double]

    /// Matches the column defaults of `public.user_settings`.
    public init(
        theme: ThemePreference = .system, weightUnit: WeightUnit = .kg, lengthUnit: LengthUnit = .cm,
        referenceGroup: ReferenceGroup = .gym, rirEnabled: Bool = true, restTimerSeconds: Int = 120,
        defaultBarKg: Double = 20, availablePlatesKg: [Double] = [1.25, 2.5, 5, 10, 15, 20, 25]
    ) {
        self.theme = theme
        self.weightUnit = weightUnit
        self.lengthUnit = lengthUnit
        self.referenceGroup = referenceGroup
        self.rirEnabled = rirEnabled
        self.restTimerSeconds = restTimerSeconds
        self.defaultBarKg = defaultBarKg
        self.availablePlatesKg = availablePlatesKg
    }
}

public struct SettingsSnapshot: Sendable, Equatable, Identifiable {
    public let id: UUID
    public let userId: UUID
    public let createdAt: Date
    public let updatedAt: Date
    public let syncState: SyncState
    public let input: SettingsInput
}

extension UserSettings {
    var snapshot: SettingsSnapshot {
        SettingsSnapshot(
            id: id, userId: userId, createdAt: createdAt, updatedAt: updatedAt, syncState: syncState,
            input: SettingsInput(
                theme: theme, weightUnit: weightUnit, lengthUnit: lengthUnit, referenceGroup: referenceGroup,
                rirEnabled: rirEnabled, restTimerSeconds: restTimerSeconds, defaultBarKg: defaultBarKg,
                availablePlatesKg: availablePlatesKg
            )
        )
    }
}

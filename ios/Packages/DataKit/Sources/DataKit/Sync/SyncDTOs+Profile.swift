import Foundation

// DTOs of the profile tables: profiles, user_settings, body_measurements, custom_exercises.

public struct ProfileDTO: SyncDTO {
    public var id: UUID
    public var userId: UUID
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?
    public var firstName: String?
    public var lastName: String?
    public var birthDate: String
    public var sex: String
    public var heightCm: Double
    public var unitSystem: String
    public var experience: String
    public var goal: String
    public var weeklyFrequency: Int
    public var equipmentAccess: String
    public var limitations: [String]
    public var locale: String
}

extension UserProfile: SyncableModel {
    public static var syncTable: SyncTable { .profiles }

    public func makeDTO() -> ProfileDTO {
        ProfileDTO(
            id: id, userId: userId, createdAt: createdAt, updatedAt: updatedAt, deletedAt: deletedAt,
            firstName: firstName, lastName: lastName, birthDate: SyncTime.day(birthDate), sex: sexRaw,
            heightCm: heightCm, unitSystem: unitSystemRaw, experience: experienceRaw, goal: goalRaw,
            weeklyFrequency: weeklyFrequency, equipmentAccess: equipmentAccessRaw, limitations: limitations, locale: locale
        )
    }

    public func apply(_ dto: ProfileDTO) {
        applyCommon(dto)
        firstName = dto.firstName
        lastName = dto.lastName
        if SyncTime.day(birthDate) != dto.birthDate { birthDate = SyncTime.parseDay(dto.birthDate) ?? birthDate }
        sexRaw = dto.sex
        heightCm = dto.heightCm
        unitSystemRaw = dto.unitSystem
        experienceRaw = dto.experience
        goalRaw = dto.goal
        weeklyFrequency = dto.weeklyFrequency
        equipmentAccessRaw = dto.equipmentAccess
        limitations = dto.limitations
        locale = dto.locale
    }

    public convenience init(syncDTO dto: ProfileDTO) {
        let input = ProfileInput(firstName: nil, birthDate: SyncTime.parseDay(dto.birthDate) ?? dto.createdAt, heightCm: dto.heightCm)
        self.init(id: dto.id, userId: dto.userId, input: input, now: dto.createdAt)
        apply(dto)
    }
}

public struct SettingsDTO: SyncDTO {
    public var id: UUID
    public var userId: UUID
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?
    public var theme: String
    public var weightUnit: String
    public var lengthUnit: String
    public var referenceGroup: String
    public var rirEnabled: Bool
    public var restTimerSeconds: Int
    public var defaultBarKg: Double
    public var availablePlatesKg: [Double]
}

extension UserSettings: SyncableModel {
    public static var syncTable: SyncTable { .userSettings }

    public func makeDTO() -> SettingsDTO {
        SettingsDTO(
            id: id, userId: userId, createdAt: createdAt, updatedAt: updatedAt, deletedAt: deletedAt, theme: themeRaw,
            weightUnit: weightUnitRaw, lengthUnit: lengthUnitRaw, referenceGroup: referenceGroupRaw,
            rirEnabled: rirEnabled, restTimerSeconds: restTimerSeconds, defaultBarKg: defaultBarKg,
            availablePlatesKg: availablePlatesKg
        )
    }

    public func apply(_ dto: SettingsDTO) {
        applyCommon(dto)
        themeRaw = dto.theme
        weightUnitRaw = dto.weightUnit
        lengthUnitRaw = dto.lengthUnit
        referenceGroupRaw = dto.referenceGroup
        rirEnabled = dto.rirEnabled
        restTimerSeconds = dto.restTimerSeconds
        defaultBarKg = dto.defaultBarKg
        availablePlatesKg = dto.availablePlatesKg
    }

    public convenience init(syncDTO dto: SettingsDTO) {
        self.init(id: dto.id, userId: dto.userId, now: dto.createdAt)
        apply(dto)
    }
}

public struct MeasurementDTO: SyncDTO {
    public var id: UUID
    public var userId: UUID
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?
    public var date: String
    public var weightKg: Double
    public var bodyFatPct: Double?
    public var source: String
}

extension BodyMeasurement: SyncableModel {
    public static var syncTable: SyncTable { .bodyMeasurements }

    public func makeDTO() -> MeasurementDTO {
        MeasurementDTO(
            id: id, userId: userId, createdAt: createdAt, updatedAt: updatedAt, deletedAt: deletedAt,
            date: SyncTime.day(date), weightKg: weightKg, bodyFatPct: bodyFatPct, source: sourceRaw
        )
    }

    public func apply(_ dto: MeasurementDTO) {
        applyCommon(dto)
        // Keep the local time of day when the calendar day did not change.
        if SyncTime.day(date) != dto.date { date = SyncTime.parseDay(dto.date) ?? date }
        weightKg = dto.weightKg
        bodyFatPct = dto.bodyFatPct
        sourceRaw = dto.source
    }

    public convenience init(syncDTO dto: MeasurementDTO) {
        let input = MeasurementInput(date: SyncTime.parseDay(dto.date) ?? dto.createdAt, weightKg: dto.weightKg)
        self.init(id: dto.id, userId: dto.userId, input: input, now: dto.createdAt)
        apply(dto)
    }
}

public struct CustomExerciseDTO: SyncDTO {
    public var id: UUID
    public var userId: UUID
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?
    public var name: String
    public var aliases: [String]
    public var instructions: [String]
    public var equipment: String?
    public var mechanic: String?
    public var force: String?
    public var level: String
    public var category: String
    public var primaryMuscles: [String]
    public var secondaryMuscles: [String]
    public var movementPattern: String
    public var isUnilateral: Bool
    public var scoringType: String
    public var anchorLift: String?
    public var loadConvention: String?
    public var ratio: Double?
    public var tau: Double?
    public var ratioConfidence: String?
    public var bwFraction: Double?
}

extension CustomExercise: SyncableModel {
    public static var syncTable: SyncTable { .customExercises }

    public func makeDTO() -> CustomExerciseDTO {
        CustomExerciseDTO(
            id: id, userId: userId, createdAt: createdAt, updatedAt: updatedAt, deletedAt: deletedAt, name: name,
            aliases: aliases, instructions: instructions, equipment: equipment, mechanic: mechanic, force: force,
            level: level, category: category, primaryMuscles: primaryMuscles, secondaryMuscles: secondaryMuscles,
            movementPattern: movementPattern, isUnilateral: isUnilateral, scoringType: scoringTypeRaw, anchorLift: anchorLift,
            loadConvention: loadConvention, ratio: ratio, tau: tau, ratioConfidence: ratioConfidence, bwFraction: bwFraction
        )
    }

    public func apply(_ dto: CustomExerciseDTO) {
        applyCommon(dto)
        name = dto.name
        aliases = dto.aliases
        instructions = dto.instructions
        equipment = dto.equipment
        mechanic = dto.mechanic
        force = dto.force
        level = dto.level
        category = dto.category
        primaryMuscles = dto.primaryMuscles
        secondaryMuscles = dto.secondaryMuscles
        movementPattern = dto.movementPattern
        isUnilateral = dto.isUnilateral
        scoringTypeRaw = dto.scoringType
        anchorLift = dto.anchorLift
        loadConvention = dto.loadConvention
        ratio = dto.ratio
        tau = dto.tau
        ratioConfidence = dto.ratioConfidence
        bwFraction = dto.bwFraction
    }

    public convenience init(syncDTO dto: CustomExerciseDTO) {
        let input = CustomExerciseInput(name: dto.name, primaryMuscles: dto.primaryMuscles)
        self.init(id: dto.id, userId: dto.userId, input: input, now: dto.createdAt)
        apply(dto)
    }
}

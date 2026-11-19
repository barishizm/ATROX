import Foundation

public struct FoodEntryDTO: SyncDTO {
    public var id: UUID
    public var userId: UUID
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?
    public var eatenAt: Date
    public var meal: String
    public var name: String
    public var calories: Double
    public var proteinG: Double
    public var carbsG: Double
    public var fatG: Double
    public var grams: Double?
    public var source: String
    public var items: String
}

extension FoodEntry: SyncableModel {
    public static var syncTable: SyncTable { .foodEntries }

    public func makeDTO() -> FoodEntryDTO {
        FoodEntryDTO(
            id: id, userId: userId, createdAt: createdAt, updatedAt: updatedAt, deletedAt: deletedAt, eatenAt: eatenAt, meal: mealRaw,
            name: name, calories: calories, proteinG: proteinG, carbsG: carbsG, fatG: fatG, grams: grams, source: sourceRaw, items: items
        )
    }

    /// Does not touch the local-only thumbnail.
    public func apply(_ dto: FoodEntryDTO) {
        applyCommon(dto)
        eatenAt = dto.eatenAt
        mealRaw = dto.meal
        name = dto.name
        calories = dto.calories
        proteinG = dto.proteinG
        carbsG = dto.carbsG
        fatG = dto.fatG
        grams = dto.grams
        sourceRaw = dto.source
        items = dto.items
    }

    public convenience init(syncDTO dto: FoodEntryDTO) {
        self.init(
            userId: dto.userId,
            input: FoodEntryInput(eatenAt: dto.eatenAt, meal: .snack, name: dto.name, calories: dto.calories, source: .manual),
            now: dto.createdAt
        )
        id = dto.id
        apply(dto)
    }
}

public struct NutritionTargetDTO: SyncDTO {
    public var id: UUID
    public var userId: UUID
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?
    public var mode: String
    public var calories: Int
    public var proteinG: Int
    public var carbsG: Int
    public var fatG: Int
    public var activity: String
}

extension NutritionTarget: SyncableModel {
    public static var syncTable: SyncTable { .nutritionTargets }

    public func makeDTO() -> NutritionTargetDTO {
        NutritionTargetDTO(
            id: id, userId: userId, createdAt: createdAt, updatedAt: updatedAt, deletedAt: deletedAt, mode: modeRaw, calories: calories,
            proteinG: proteinG, carbsG: carbsG, fatG: fatG, activity: activityRaw
        )
    }

    public func apply(_ dto: NutritionTargetDTO) {
        applyCommon(dto)
        modeRaw = dto.mode
        calories = dto.calories
        proteinG = dto.proteinG
        carbsG = dto.carbsG
        fatG = dto.fatG
        activityRaw = dto.activity
    }

    public convenience init(syncDTO dto: NutritionTargetDTO) {
        self.init(
            userId: dto.userId,
            input: NutritionTargetInput(
                mode: .auto, values: NutritionTargetValues(calories: dto.calories, proteinG: dto.proteinG, carbsG: dto.carbsG, fatG: dto.fatG),
                activity: .moderate
            ),
            now: dto.createdAt
        )
        id = dto.id
        apply(dto)
    }
}

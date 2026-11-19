import CryptoKit
import Foundation
import SwiftData

/// Food tracking: adds `FoodEntry` and `NutritionTarget`. Every other model is shared with V7, so V7 → V8 is a
/// lightweight migration (two new entities).
public enum SchemaV8: VersionedSchema {
    public static let versionIdentifier = Schema.Version(8, 0, 0)

    public static var models: [any PersistentModel.Type] {
        SchemaV7.models + [FoodEntry.self, NutritionTarget.self]
    }
}

public typealias FoodEntry = SchemaV8.FoodEntry
public typealias NutritionTarget = SchemaV8.NutritionTarget

extension SchemaV8 {
    /// One logged food or meal. Mirrors `public.food_entries`; the thumbnail never leaves the device.
    @Model
    public final class FoodEntry: SyncableRecord {
        #Index<FoodEntry>([\.userId, \.eatenAt], [\.userId, \.updatedAt])

        @Attribute(.unique) public var id: UUID
        public var userId: UUID
        public var createdAt: Date
        public var updatedAt: Date
        public var deletedAt: Date?
        public var syncStateRaw: String

        public var eatenAt: Date
        public var mealRaw: String
        public var name: String
        public var calories: Double
        public var proteinG: Double
        public var carbsG: Double
        public var fatG: Double
        public var grams: Double?
        public var sourceRaw: String
        /// `[FoodItemDetail]` as JSON.
        public var items: String
        @Attribute(.externalStorage) public var thumbnail: Data?

        public init(id: UUID = UUID(), userId: UUID, input: FoodEntryInput, now: Date = Date()) {
            self.id = id
            self.userId = userId
            createdAt = now
            updatedAt = now
            deletedAt = nil
            syncStateRaw = SyncState.pending.rawValue
            eatenAt = input.eatenAt
            mealRaw = input.meal.rawValue
            name = input.name
            calories = input.calories
            proteinG = input.proteinG
            carbsG = input.carbsG
            fatG = input.fatG
            grams = input.grams
            sourceRaw = input.source.rawValue
            items = Self.encode(input.items)
            thumbnail = input.thumbnail
        }

        func apply(_ input: FoodEntryInput) {
            eatenAt = input.eatenAt
            mealRaw = input.meal.rawValue
            name = input.name
            calories = input.calories
            proteinG = input.proteinG
            carbsG = input.carbsG
            fatG = input.fatG
            grams = input.grams
            sourceRaw = input.source.rawValue
            items = Self.encode(input.items)
            if let thumbnail = input.thumbnail { self.thumbnail = thumbnail }
        }

        static func encode(_ items: [FoodItemDetail]) -> String {
            guard let data = try? JSONEncoder().encode(items), let text = String(data: data, encoding: .utf8) else { return "[]" }
            return text
        }

        public var itemDetails: [FoodItemDetail] {
            (try? JSONDecoder().decode([FoodItemDetail].self, from: Data(items.utf8))) ?? []
        }

        public var snapshot: FoodEntrySnapshot {
            FoodEntrySnapshot(
                id: id, userId: userId, createdAt: createdAt, updatedAt: updatedAt, syncState: syncState,
                input: FoodEntryInput(
                    eatenAt: eatenAt, meal: MealType(rawValue: mealRaw) ?? .snack, name: name, calories: calories, proteinG: proteinG,
                    carbsG: carbsG, fatG: fatG, grams: grams, source: FoodSource(rawValue: sourceRaw) ?? .manual, items: itemDetails,
                    thumbnail: thumbnail
                )
            )
        }
    }

    /// The user's calorie and macro target; one row per user (deterministic id). Mirrors `public.nutrition_targets`.
    @Model
    public final class NutritionTarget: SyncableRecord {
        @Attribute(.unique) public var id: UUID
        public var userId: UUID
        public var createdAt: Date
        public var updatedAt: Date
        public var deletedAt: Date?
        public var syncStateRaw: String

        public var modeRaw: String
        public var calories: Int
        public var proteinG: Int
        public var carbsG: Int
        public var fatG: Int
        public var activityRaw: String

        public init(userId: UUID, input: NutritionTargetInput, now: Date = Date()) {
            id = Self.id(userId: userId)
            self.userId = userId
            createdAt = now
            updatedAt = now
            deletedAt = nil
            syncStateRaw = SyncState.pending.rawValue
            modeRaw = input.mode.rawValue
            calories = input.values.calories
            proteinG = input.values.proteinG
            carbsG = input.values.carbsG
            fatG = input.values.fatG
            activityRaw = input.activity.rawValue
        }

        /// Deterministic id of the user's single target row, so two devices write the same row.
        public static func id(userId: UUID) -> UUID {
            var bytes = Array(SHA256.hash(data: Data([userId.uuidString, "nutrition_target"].joined(separator: "|").utf8)).prefix(16))
            bytes[6] = (bytes[6] & 0x0F) | 0x80
            bytes[8] = (bytes[8] & 0x3F) | 0x80
            return UUID(uuid: (
                bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
            ))
        }

        func apply(_ input: NutritionTargetInput) {
            modeRaw = input.mode.rawValue
            calories = input.values.calories
            proteinG = input.values.proteinG
            carbsG = input.values.carbsG
            fatG = input.values.fatG
            activityRaw = input.activity.rawValue
        }

        public var input: NutritionTargetInput {
            NutritionTargetInput(
                mode: TargetMode(rawValue: modeRaw) ?? .auto,
                values: NutritionTargetValues(calories: calories, proteinG: proteinG, carbsG: carbsG, fatG: fatG),
                activity: ActivityLevel(rawValue: activityRaw) ?? .moderate
            )
        }
    }
}

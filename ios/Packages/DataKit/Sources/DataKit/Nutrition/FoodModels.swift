import Foundation

/// One food inside an entry (the result of a photo analysis, or a single product).
public struct FoodItemDetail: Sendable, Codable, Equatable, Hashable, Identifiable {
    public var id: UUID
    public var name: String
    public var grams: Double
    public var calories: Double
    public var proteinG: Double
    public var carbsG: Double
    public var fatG: Double

    public init(id: UUID = UUID(), name: String, grams: Double, calories: Double, proteinG: Double, carbsG: Double, fatG: Double) {
        self.id = id
        self.name = name
        self.grams = grams
        self.calories = calories
        self.proteinG = proteinG
        self.carbsG = carbsG
        self.fatG = fatG
    }

    /// The same food scaled to `newGrams` (all nutrients scale linearly).
    public func scaled(toGrams newGrams: Double) -> FoodItemDetail {
        guard grams > 0 else { return self }
        let factor = newGrams / grams
        var copy = self
        copy.grams = newGrams
        copy.calories = calories * factor
        copy.proteinG = proteinG * factor
        copy.carbsG = carbsG * factor
        copy.fatG = fatG * factor
        return copy
    }
}

public struct FoodEntryInput: Sendable, Equatable {
    public var eatenAt: Date
    public var meal: MealType
    public var name: String
    public var calories: Double
    public var proteinG: Double
    public var carbsG: Double
    public var fatG: Double
    public var grams: Double?
    public var source: FoodSource
    public var items: [FoodItemDetail]
    /// Small JPEG kept on this device only (never synced).
    public var thumbnail: Data?

    public init(
        eatenAt: Date, meal: MealType, name: String, calories: Double, proteinG: Double = 0, carbsG: Double = 0, fatG: Double = 0,
        grams: Double? = nil, source: FoodSource, items: [FoodItemDetail] = [], thumbnail: Data? = nil
    ) {
        self.eatenAt = eatenAt
        self.meal = meal
        self.name = name
        self.calories = calories
        self.proteinG = proteinG
        self.carbsG = carbsG
        self.fatG = fatG
        self.grams = grams
        self.source = source
        self.items = items
        self.thumbnail = thumbnail
    }

    /// An input whose totals are the sum of `items`.
    public init(eatenAt: Date, meal: MealType, name: String, source: FoodSource, items: [FoodItemDetail], thumbnail: Data? = nil) {
        self.init(
            eatenAt: eatenAt, meal: meal, name: name,
            calories: items.reduce(0) { $0 + $1.calories }, proteinG: items.reduce(0) { $0 + $1.proteinG },
            carbsG: items.reduce(0) { $0 + $1.carbsG }, fatG: items.reduce(0) { $0 + $1.fatG },
            grams: items.reduce(0) { $0 + $1.grams }, source: source, items: items, thumbnail: thumbnail
        )
    }
}

public struct FoodEntrySnapshot: Sendable, Equatable, Identifiable {
    public let id: UUID
    public let userId: UUID
    public let createdAt: Date
    public let updatedAt: Date
    public let syncState: SyncState
    public let input: FoodEntryInput

    public init(id: UUID = UUID(), userId: UUID, createdAt: Date = Date(), updatedAt: Date? = nil, syncState: SyncState = .pending, input: FoodEntryInput) {
        self.id = id
        self.userId = userId
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
        self.syncState = syncState
        self.input = input
    }
}

public struct NutritionTargetInput: Sendable, Equatable {
    public var mode: TargetMode
    public var values: NutritionTargetValues
    public var activity: ActivityLevel

    public init(mode: TargetMode, values: NutritionTargetValues, activity: ActivityLevel) {
        self.mode = mode
        self.values = values
        self.activity = activity
    }
}

/// What was eaten in one calendar day.
public struct NutritionDay: Sendable, Equatable {
    public var calories: Double
    public var proteinG: Double
    public var carbsG: Double
    public var fatG: Double
    public var entries: [FoodEntrySnapshot]

    public static let empty = NutritionDay(calories: 0, proteinG: 0, carbsG: 0, fatG: 0, entries: [])

    /// Entries whose `eatenAt` falls on `day` in `calendar`, oldest first, with their totals.
    public static func summarize(_ all: [FoodEntrySnapshot], on day: Date, calendar: Calendar = .current) -> NutritionDay {
        let entries = all.filter { calendar.isDate($0.input.eatenAt, inSameDayAs: day) }.sorted { $0.input.eatenAt < $1.input.eatenAt }
        return NutritionDay(
            calories: entries.reduce(0) { $0 + $1.input.calories }, proteinG: entries.reduce(0) { $0 + $1.input.proteinG },
            carbsG: entries.reduce(0) { $0 + $1.input.carbsG }, fatG: entries.reduce(0) { $0 + $1.input.fatG }, entries: entries
        )
    }
}

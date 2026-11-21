import DataKit
import Foundation

/// One of the everyday foods offered for one-tap logging: a typical serving with its nutrients.
/// Names and serving labels live in the String Catalog under `food.common.<id>` and `food.common.<id>.serving`.
struct CommonFood: Identifiable, Equatable, Sendable {
    let id: String
    let grams: Double
    let calories: Double
    let proteinG: Double
    let carbsG: Double
    let fatG: Double

    var nameKey: String { "food.common.\(id)" }
    var servingKey: String { "food.common.\(id).serving" }

    /// The name in the app language, which can differ from the device language (in-app language setting).
    func name(in locale: Locale) -> String {
        let language = locale.language.languageCode?.identifier ?? "en"
        let bundle = Bundle.main.path(forResource: language, ofType: "lproj").flatMap(Bundle.init(path:)) ?? Bundle.main
        return bundle.localizedString(forKey: nameKey, value: id, table: nil)
    }

    /// The entry a tap on "+" logs: one serving, eaten at `eatenAt`, in `meal`.
    func entryInput(name: String, meal: MealType, eatenAt: Date) -> FoodEntryInput {
        let item = FoodItemDetail(name: name, grams: grams, calories: calories, proteinG: proteinG, carbsG: carbsG, fatG: fatG)
        return FoodEntryInput(eatenAt: eatenAt, meal: meal, name: name, source: .manual, items: [item])
    }

    /// Foods whose name contains `query`, ignoring case and diacritics; everything for an empty query.
    static func filter(_ foods: [CommonFood], query: String, name: (CommonFood) -> String) -> [CommonFood] {
        let terms = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !terms.isEmpty else { return foods }
        return foods.filter { name($0).range(of: terms, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
    }

    /// The 25 most commonly logged foods and drinks, most common first.
    static let all: [CommonFood] = [
        CommonFood(id: "coffee", grams: 237, calories: 2, proteinG: 0.3, carbsG: 0, fatG: 0),
        CommonFood(id: "banana", grams: 118, calories: 105, proteinG: 1.3, carbsG: 27, fatG: 0.4),
        CommonFood(id: "egg_boiled", grams: 50, calories: 78, proteinG: 6.3, carbsG: 0.6, fatG: 5.3),
        CommonFood(id: "egg_scrambled", grams: 61, calories: 91, proteinG: 6, carbsG: 1, fatG: 7),
        CommonFood(id: "bread", grams: 30, calories: 80, proteinG: 2.7, carbsG: 15, fatG: 1),
        CommonFood(id: "oats", grams: 234, calories: 166, proteinG: 5.9, carbsG: 28, fatG: 3.6),
        CommonFood(id: "milk", grams: 244, calories: 122, proteinG: 8, carbsG: 12, fatG: 4.8),
        CommonFood(id: "yogurt", grams: 245, calories: 149, proteinG: 8.5, carbsG: 11.4, fatG: 8),
        CommonFood(id: "apple", grams: 182, calories: 95, proteinG: 0.5, carbsG: 25, fatG: 0.3),
        CommonFood(id: "chicken", grams: 100, calories: 165, proteinG: 31, carbsG: 0, fatG: 3.6),
        CommonFood(id: "rice", grams: 158, calories: 205, proteinG: 4.3, carbsG: 45, fatG: 0.4),
        CommonFood(id: "pasta", grams: 140, calories: 220, proteinG: 8.1, carbsG: 43, fatG: 1.3),
        CommonFood(id: "potato", grams: 173, calories: 161, proteinG: 4.3, carbsG: 37, fatG: 0.2),
        CommonFood(id: "beef", grams: 100, calories: 250, proteinG: 26, carbsG: 0, fatG: 15),
        CommonFood(id: "salmon", grams: 100, calories: 206, proteinG: 22, carbsG: 0, fatG: 12),
        CommonFood(id: "tuna", grams: 100, calories: 116, proteinG: 26, carbsG: 0, fatG: 0.8),
        CommonFood(id: "cheese", grams: 30, calories: 75, proteinG: 4, carbsG: 1.2, fatG: 6),
        CommonFood(id: "olive_oil", grams: 14, calories: 119, proteinG: 0, carbsG: 0, fatG: 13.5),
        CommonFood(id: "butter", grams: 14, calories: 102, proteinG: 0.1, carbsG: 0, fatG: 11.5),
        CommonFood(id: "almonds", grams: 28, calories: 164, proteinG: 6, carbsG: 6, fatG: 14),
        CommonFood(id: "peanut_butter", grams: 16, calories: 94, proteinG: 3.6, carbsG: 3.2, fatG: 8),
        CommonFood(id: "orange_juice", grams: 248, calories: 112, proteinG: 1.7, carbsG: 26, fatG: 0.5),
        CommonFood(id: "tea", grams: 237, calories: 2, proteinG: 0, carbsG: 0.7, fatG: 0),
        CommonFood(id: "whey", grams: 30, calories: 120, proteinG: 24, carbsG: 3, fatG: 1.5),
        CommonFood(id: "avocado", grams: 100, calories: 160, proteinG: 2, carbsG: 8.5, fatG: 14.7),
    ]
}

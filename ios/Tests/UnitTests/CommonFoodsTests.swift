import DataKit
import Foundation
import Testing

@testable import ATROX

struct CommonFoodsTests {
    @Test func catalogHasTwentyFiveUniqueFoods() {
        #expect(CommonFood.all.count == 25)
        #expect(Set(CommonFood.all.map(\.id)).count == 25)
    }

    @Test func caloriesRoughlyMatchTheMacros() {
        for food in CommonFood.all {
            let fromMacros = 4 * food.proteinG + 4 * food.carbsG + 9 * food.fatG
            let tolerance = max(12, food.calories * 0.15)
            #expect(abs(fromMacros - food.calories) <= tolerance, "\(food.id): \(food.calories) kcal vs \(fromMacros) from macros")
        }
    }

    @Test func everyFoodHasLocalizedNameAndServing() throws {
        let strings = try String(contentsOf: Self.catalogURL, encoding: .utf8)
        for food in CommonFood.all {
            #expect(strings.contains("\"\(food.nameKey)\""), "missing \(food.nameKey)")
            #expect(strings.contains("\"\(food.servingKey)\""), "missing \(food.servingKey)")
        }
    }

    @Test func quickAddLogsOneServingToTheChosenMealAndTime() throws {
        let banana = try #require(CommonFood.all.first { $0.id == "banana" })
        let moment = Date(timeIntervalSince1970: 1_800_000_000)
        let input = banana.entryInput(name: "Banana", meal: .snack, eatenAt: moment)
        #expect(input.meal == .snack)
        #expect(input.eatenAt == moment)
        #expect(input.source == .manual)
        #expect(input.name == "Banana")
        #expect(input.calories == 105)
        #expect(input.grams == 118)
        #expect(input.items.count == 1)
    }

    @Test func filterIgnoresCaseAndDiacritics() {
        let names = ["coffee": "Kahve", "tea": "Çay", "banana": "Muz"]
        let name: (CommonFood) -> String = { names[$0.id] ?? $0.id }
        let foods = CommonFood.all.filter { names.keys.contains($0.id) }
        #expect(CommonFood.filter(foods, query: "cay", name: name).map(\.id) == ["tea"])
        #expect(CommonFood.filter(foods, query: "KAH", name: name).map(\.id) == ["coffee"])
        #expect(CommonFood.filter(foods, query: "  ", name: name).count == 3)
        #expect(CommonFood.filter(foods, query: "pizza", name: name).isEmpty)
    }

    private static var catalogURL: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("App/Resources/Localizable.xcstrings")
    }
}

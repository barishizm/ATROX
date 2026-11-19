@testable import DataKit
import Foundation
import Testing

@Suite struct OpenFoodFactsTests {
    private let productJSON = """
    {"status":1,"product":{"product_name":"Hazelnut Spread","brands":"Acme, Other","serving_quantity":"15",
     "nutriments":{"energy-kcal_100g":539,"proteins_100g":6.3,"carbohydrates_100g":57.5,"fat_100g":30.9}}}
    """

    @Test func parsesAProduct() throws {
        let food = try #require(OpenFoodFacts.parseProduct(Data(productJSON.utf8), barcode: "3017620422003"))
        #expect(food.name == "Hazelnut Spread" && food.brand == "Acme")
        #expect(food.caloriesPer100g == 539 && food.servingGrams == 15)
        #expect(food.defaultGrams == 15)
        let item = food.item(grams: 30)
        #expect(abs(item.calories - 161.7) < 0.01 && abs(item.proteinG - 1.89) < 0.01)
    }

    @Test func missingProductOrNutrientsIsNil() {
        #expect(OpenFoodFacts.parseProduct(Data(#"{"status":0}"#.utf8), barcode: "3017620422003") == nil)
        #expect(OpenFoodFacts.parseProduct(Data(#"{"status":1,"product":{"product_name":"X","nutriments":{}}}"#.utf8), barcode: "3017620422003") == nil)
        #expect(OpenFoodFacts.parseProduct(Data("nonsense".utf8), barcode: "3017620422003") == nil)
    }

    @Test func kilojoulesAndImpossibleValues() throws {
        let kj = #"{"status":1,"product":{"product_name":"Bar","nutriments":{"energy_100g":1255,"proteins_100g":"10,5"}}}"#
        let food = try #require(OpenFoodFacts.parseProduct(Data(kj.utf8), barcode: "12345678"))
        #expect(abs(food.caloriesPer100g - 300) < 0.2 && food.proteinPer100g == 10.5)
        let absurd = #"{"status":1,"product":{"product_name":"Bad","nutriments":{"energy-kcal_100g":4000}}}"#
        #expect(OpenFoodFacts.parseProduct(Data(absurd.utf8), barcode: "12345678") == nil)
    }

    @Test func barcodeValidation() {
        #expect(OpenFoodFacts.isValidBarcode("3017620422003"))
        #expect(OpenFoodFacts.isValidBarcode("12345678"))
        #expect(!OpenFoodFacts.isValidBarcode("1234567"))
        #expect(!OpenFoodFacts.isValidBarcode("../etc/passwd"))
        #expect(!OpenFoodFacts.isValidBarcode("1234567a"))
    }

    @Test func searchParsesSeveralAndSkipsBadOnes() {
        let json = """
        {"products":[{"code":"3017620422003","product_name":"A","nutriments":{"energy-kcal_100g":100}},
                     {"code":"bad","product_name":"B","nutriments":{"energy-kcal_100g":100}},
                     {"code":"12345678","product_name":"","nutriments":{"energy-kcal_100g":100}}]}
        """
        #expect(OpenFoodFacts.parseSearch(Data(json.utf8)).map(\.name) == ["A"])
    }

    @Test func clientSendsAUserAgentAndBuildsTheURL() async throws {
        final class Box: @unchecked Sendable { var request: URLRequest? }
        let box = Box()
        let client = OpenFoodFactsClient { request in
            box.request = request
            return (Data(productJSON.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let food = try await client.product(barcode: "3017620422003")
        #expect(food?.name == "Hazelnut Spread")
        #expect(box.request?.url?.path == "/api/v2/product/3017620422003.json")
        #expect(box.request?.value(forHTTPHeaderField: "User-Agent")?.hasPrefix("ATROX-iOS") == true)
        #expect(try await client.product(barcode: "not-a-code") == nil)
    }
}

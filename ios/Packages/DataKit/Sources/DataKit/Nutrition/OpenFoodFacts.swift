import Foundation

/// A packaged product with its nutrients per 100 g (Open Food Facts).
public struct PackagedFood: Sendable, Equatable, Identifiable {
    public var id: String { barcode }
    public let barcode: String
    public let name: String
    public let brand: String?
    public let caloriesPer100g: Double
    public let proteinPer100g: Double
    public let carbsPer100g: Double
    public let fatPer100g: Double
    /// Grams in one serving when the package says so.
    public let servingGrams: Double?

    public init(
        barcode: String, name: String, brand: String? = nil, caloriesPer100g: Double, proteinPer100g: Double, carbsPer100g: Double,
        fatPer100g: Double, servingGrams: Double? = nil
    ) {
        self.barcode = barcode
        self.name = name
        self.brand = brand
        self.caloriesPer100g = caloriesPer100g
        self.proteinPer100g = proteinPer100g
        self.carbsPer100g = carbsPer100g
        self.fatPer100g = fatPer100g
        self.servingGrams = servingGrams
    }

    public var defaultGrams: Double { servingGrams ?? 100 }

    public var displayName: String { brand.map { "\(name) · \($0)" } ?? name }

    /// The food for a portion of `grams`.
    public func item(grams: Double) -> FoodItemDetail {
        let factor = grams / 100
        return FoodItemDetail(
            name: name, grams: grams, calories: caloriesPer100g * factor, proteinG: proteinPer100g * factor,
            carbsG: carbsPer100g * factor, fatG: fatPer100g * factor
        )
    }
}

public protocol PackagedFoodService: Sendable {
    /// nil when the product is not in the database or has no usable nutrition data.
    func product(barcode: String) async throws -> PackagedFood?
    func search(_ query: String, languageCode: String) async throws -> [PackagedFood]
}

public enum OpenFoodFacts {
    /// EAN-8, UPC-A, EAN-13, GTIN-14: digits only. Anything else never reaches the URL.
    public static func isValidBarcode(_ code: String) -> Bool {
        (8...14).contains(code.count) && code.allSatisfy { $0.isASCII && $0.isNumber }
    }

    private static func number(_ value: Any?) -> Double? {
        if let number = value as? Double { return number }
        if let text = value as? String { return Double(text.replacingOccurrences(of: ",", with: ".")) }
        return nil
    }

    static func food(from product: [String: Any], fallbackCode: String? = nil) -> PackagedFood? {
        guard let nutriments = product["nutriments"] as? [String: Any] else { return nil }
        let code = (product["code"] as? String) ?? fallbackCode ?? ""
        let rawName = (product["product_name"] as? String) ?? (product["product_name_en"] as? String) ?? ""
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, isValidBarcode(code) else { return nil }
        let kcal = number(nutriments["energy-kcal_100g"]) ?? number(nutriments["energy_100g"]).map { $0 / 4.184 }
        let protein = number(nutriments["proteins_100g"])
        let carbs = number(nutriments["carbohydrates_100g"])
        let fat = number(nutriments["fat_100g"])
        // A product with no energy and no macros is useless; a missing single macro counts as zero.
        guard kcal != nil || protein != nil || carbs != nil || fat != nil else { return nil }
        let p = max(0, protein ?? 0), c = max(0, carbs ?? 0), f = max(0, fat ?? 0)
        let energy = max(0, kcal ?? (4 * p + 4 * c + 9 * f))
        guard energy <= 950 else { return nil } // more than pure fat per 100 g is a data error
        let brand = (product["brands"] as? String)?.split(separator: ",").first.map { $0.trimmingCharacters(in: .whitespaces) }
        let serving = number(product["serving_quantity"]).flatMap { (1...2000).contains($0) ? $0 : nil }
        return PackagedFood(
            barcode: code, name: String(name.prefix(120)), brand: brand?.isEmpty == false ? brand : nil, caloriesPer100g: energy,
            proteinPer100g: p, carbsPer100g: c, fatPer100g: f, servingGrams: serving
        )
    }

    public static func parseProduct(_ data: Data, barcode: String) -> PackagedFood? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any], (root["status"] as? Int) == 1,
              let product = root["product"] as? [String: Any]
        else { return nil }
        return food(from: product, fallbackCode: barcode)
    }

    public static func parseSearch(_ data: Data) -> [PackagedFood] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let products = root["products"] as? [[String: Any]]
        else { return [] }
        return products.compactMap { food(from: $0) }
    }
}

/// Open Food Facts over HTTPS from the device. Only the barcode or search words leave the phone, with a generic
/// User-Agent (no account data), as the project asks API users to identify themselves.
public struct OpenFoodFactsClient: PackagedFoodService {
    public typealias Send = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)

    private let baseURL: URL
    private let send: Send
    static let fields = "code,product_name,product_name_en,brands,serving_quantity,nutriments"

    public init(baseURL: URL = URL(string: "https://world.openfoodfacts.org")!, send: @escaping Send = Self.urlSession) {
        self.baseURL = baseURL
        self.send = send
    }

    public static let urlSession: Send = { request in
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return (data, http)
    }

    private func get(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("ATROX-iOS/1.0 (https://atrox.online)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await send(request)
        guard (200..<300).contains(response.statusCode) else { throw URLError(.badServerResponse) }
        return data
    }

    public func product(barcode: String) async throws -> PackagedFood? {
        guard OpenFoodFacts.isValidBarcode(barcode) else { return nil }
        var components = URLComponents(url: baseURL.appendingPathComponent("api/v2/product/\(barcode).json"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "fields", value: Self.fields)]
        // The v2 product reply carries `code` at the top level, not inside `product`.
        return OpenFoodFacts.parseProduct(try await get(components.url!), barcode: barcode)
    }

    public func search(_ query: String, languageCode: String) async throws -> [PackagedFood] {
        let terms = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard terms.count >= 2 else { return [] }
        var components = URLComponents(url: baseURL.appendingPathComponent("cgi/search.pl"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "search_terms", value: String(terms.prefix(80))), URLQueryItem(name: "search_simple", value: "1"),
            URLQueryItem(name: "action", value: "process"), URLQueryItem(name: "json", value: "1"), URLQueryItem(name: "page_size", value: "12"),
            URLQueryItem(name: "lc", value: languageCode), URLQueryItem(name: "fields", value: Self.fields),
        ]
        return OpenFoodFacts.parseSearch(try await get(components.url!))
    }
}

import Foundation

/// One food the model found in a meal. Numbers are for the estimated portion.
public struct FoodAnalysisItem: Sendable, Equatable, Decodable {
    public let name: String
    public let grams: Double
    public let calories: Double
    public let proteinG: Double
    public let carbsG: Double
    public let fatG: Double
    public let confidence: Double

    public init(name: String, grams: Double, calories: Double, proteinG: Double, carbsG: Double, fatG: Double, confidence: Double = 0.5) {
        self.name = name
        self.grams = grams
        self.calories = calories
        self.proteinG = proteinG
        self.carbsG = carbsG
        self.fatG = fatG
        self.confidence = confidence
    }
}

/// The server's estimate for one photo or description.
public struct FoodAnalysis: Sendable, Equatable, Decodable {
    public let mealName: String
    public let items: [FoodAnalysisItem]
    public let notes: String?
    /// Analyses left today after this one, and the daily allowance of the user's tier.
    public let remaining: Int
    public let limit: Int

    public init(mealName: String, items: [FoodAnalysisItem], notes: String? = nil, remaining: Int, limit: Int) {
        self.mealName = mealName
        self.items = items
        self.notes = notes
        self.remaining = remaining
        self.limit = limit
    }
}

public enum FoodAnalyzeInput: Sendable, Equatable {
    /// A JPEG (already downsized by the app) and an optional hint such as "no oil".
    case photo(jpeg: Data, hint: String?)
    case text(String)
}

public enum FoodAnalyzeError: Error, Sendable, Equatable {
    /// The food-photo consent is missing for the version the server wants.
    case consentRequired
    /// The day's analyses are used up; `limit` is the user's tier allowance.
    case quotaExceeded(limit: Int?)
    /// The model found no food in the photo or text.
    case notFood
    /// Spend cap reached, model down or unreadable answer: try again later.
    case unavailable
    case unauthorized
    case offline
    case timeout
    case cancelled
    case failed

    static func from(_ error: CoachError) -> FoodAnalyzeError {
        switch error {
        case .consentRequired: .consentRequired
        case .quotaExceeded: .quotaExceeded(limit: nil)
        case .unavailable: .unavailable
        case .unauthorized: .unauthorized
        case .offline: .offline
        case .timeout: .timeout
        case .cancelled: .cancelled
        case .server(let code, _) where code == "not_food": .notFood
        case .server(let code, _) where code == "food_unavailable": .unavailable
        case .rateLimited, .duplicateMessage, .invalidResponse, .server: .failed
        }
    }
}

public protocol FoodAnalyzeService: Sendable {
    func analyze(_ input: FoodAnalyzeInput, locale: String) async throws -> FoodAnalysis
}

/// `food-analyze` Edge Function. A 401 refreshes the token and tries once more.
public struct SupabaseFoodAnalyzeService: FoodAnalyzeService {
    public typealias Token = @Sendable () async -> String?
    public typealias Send = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)

    private let baseURL: URL
    private let anonKey: String
    private let accessToken: Token
    private let refreshedToken: Token
    private let send: Send
    private let timeZone: @Sendable () -> String

    public init(
        baseURL: URL, anonKey: String, accessToken: @escaping Token, refreshedToken: @escaping Token,
        timeZone: @escaping @Sendable () -> String = { TimeZone.current.identifier }, send: @escaping Send = SupabaseCoachDigestService.urlSession
    ) {
        self.baseURL = baseURL
        self.anonKey = anonKey
        self.accessToken = accessToken
        self.refreshedToken = refreshedToken
        self.timeZone = timeZone
        self.send = send
    }

    public func analyze(_ input: FoodAnalyzeInput, locale: String) async throws -> FoodAnalysis {
        var token = await accessToken()
        for attempt in 0..<2 {
            guard let current = token else { throw FoodAnalyzeError.unauthorized }
            do {
                return try await attemptOnce(input, locale: locale, token: current)
            } catch CoachError.unauthorized where attempt == 0 {
                token = await refreshedToken()
            } catch let error as FoodAnalyzeError {
                throw error
            } catch {
                throw FoodAnalyzeError.from(CoachError.from(error))
            }
        }
        throw FoodAnalyzeError.unauthorized
    }

    static func body(for input: FoodAnalyzeInput, locale: String, timeZone: String) -> Data {
        var object: [String: Any] = ["locale": locale, "time_zone": timeZone]
        switch input {
        case .photo(let jpeg, let hint):
            object["kind"] = "photo"
            object["image_base64"] = jpeg.base64EncodedString()
            object["media_type"] = "image/jpeg"
            if let hint = hint?.trimmingCharacters(in: .whitespacesAndNewlines), !hint.isEmpty { object["hint"] = String(hint.prefix(200)) }
        case .text(let text):
            object["kind"] = "text"
            object["text"] = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(300))
        }
        return (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data()
    }

    private func attemptOnce(_ input: FoodAnalyzeInput, locale: String, token: String) async throws -> FoodAnalysis {
        var request = URLRequest(url: baseURL.appendingPathComponent("functions/v1/food-analyze"))
        request.httpMethod = "POST"
        request.timeoutInterval = 45
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.body(for: input, locale: locale, timeZone: timeZone())
        let (data, response) = try await send(request)
        guard (200..<300).contains(response.statusCode) else {
            let error = CoachError.from(status: response.statusCode, body: data)
            if case .quotaExceeded = error {
                let limit = (try? JSONDecoder().decode(CoachJSON.self, from: data))?["error"]?["details"]?["limit"]?.int
                throw FoodAnalyzeError.quotaExceeded(limit: limit)
            }
            throw error
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let analysis = try? decoder.decode(FoodAnalysis.self, from: data), !analysis.items.isEmpty else { throw FoodAnalyzeError.unavailable }
        return analysis
    }
}

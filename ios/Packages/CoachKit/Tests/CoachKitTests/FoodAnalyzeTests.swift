@testable import CoachKit
import Foundation
import Testing

@Suite struct FoodAnalyzeTests {
    private final class Box: @unchecked Sendable {
        private let lock = NSLock()
        private var replies: [(Int, String)]
        private var sent: [URLRequest] = []
        init(_ replies: [(Int, String)]) { self.replies = replies }
        var requests: [URLRequest] { lock.withLock { sent } }
        func next(_ request: URLRequest) -> (Int, String) {
            lock.withLock {
                sent.append(request)
                return replies.isEmpty ? (500, "{}") : replies.removeFirst()
            }
        }
    }

    private final class Tokens: @unchecked Sendable {
        private let lock = NSLock()
        private var values: [String?]
        init(_ values: [String?]) { self.values = values }
        func next() -> String? { lock.withLock { values.isEmpty ? nil : values.removeFirst() } }
    }

    private func service(_ replies: [(Int, String)], tokens: [String?] = ["old", "fresh"]) -> (SupabaseFoodAnalyzeService, Box) {
        let box = Box(replies)
        let tokens = Tokens(tokens)
        let service = SupabaseFoodAnalyzeService(
            baseURL: URL(string: "https://example.test")!, anonKey: "anon", accessToken: { tokens.next() }, refreshedToken: { tokens.next() },
            timeZone: { "Europe/Istanbul" },
            send: { request in
                let (status, body) = box.next(request)
                return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
            }
        )
        return (service, box)
    }

    private let good = """
    {"meal_name":"Chicken and rice","items":[{"name":"Rice","grams":200,"calories":260,"protein_g":5,"carbs_g":56,"fat_g":0.5,"confidence":0.8}],
     "totals":{"calories":260,"protein_g":5,"carbs_g":56,"fat_g":0.5,"grams":200},"remaining":2,"limit":3}
    """

    @Test func photoBodyMatchesTheServerSchema() throws {
        let body = SupabaseFoodAnalyzeService.body(for: .photo(jpeg: Data([1, 2, 3]), hint: " no oil "), locale: "tr", timeZone: "Europe/Istanbul")
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["kind"] as? String == "photo")
        #expect(json["image_base64"] as? String == "AQID")
        #expect(json["media_type"] as? String == "image/jpeg")
        #expect(json["hint"] as? String == "no oil")
        #expect(json["time_zone"] as? String == "Europe/Istanbul")
        let text = SupabaseFoodAnalyzeService.body(for: .text("  2 eggs  "), locale: "en", timeZone: "UTC")
        #expect((try JSONSerialization.jsonObject(with: text) as? [String: Any])?["text"] as? String == "2 eggs")
    }

    @Test func decodesTheAnalysis() async throws {
        let (service, box) = service([(200, good)])
        let result = try await service.analyze(.text("rice"), locale: "en")
        #expect(result.mealName == "Chicken and rice")
        #expect(result.items.first?.proteinG == 5)
        #expect(result.remaining == 2 && result.limit == 3)
        let request = try #require(box.requests.first)
        #expect(request.url?.path == "/functions/v1/food-analyze")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer old")
    }

    @Test func aRejectedTokenIsRefreshedOnce() async throws {
        let (service, box) = service([(401, #"{"error":{"code":"unauthorized","message":"x"}}"#), (200, good)])
        _ = try await service.analyze(.text("rice"), locale: "en")
        #expect(box.requests.count == 2)
        #expect(box.requests.last?.value(forHTTPHeaderField: "Authorization") == "Bearer fresh")
    }

    @Test func mapsServerErrors() async throws {
        func run(_ status: Int, _ body: String) async -> FoodAnalyzeError? {
            let (service, _) = service([(status, body)])
            do { _ = try await service.analyze(.text("x"), locale: "en"); return nil } catch { return error as? FoodAnalyzeError }
        }
        #expect(await run(403, #"{"error":{"code":"consent_required","message":"x"}}"#) == .consentRequired)
        #expect(await run(429, #"{"error":{"code":"quota_exceeded","message":"x","details":{"limit":3}}}"#) == .quotaExceeded(limit: 3))
        #expect(await run(429, #"{"error":{"code":"rate_limited","message":"x"}}"#) == .rateLimited)
        #expect(await run(422, #"{"error":{"code":"not_food","message":"x"}}"#) == .notFood)
        #expect(await run(503, #"{"error":{"code":"food_unavailable","message":"x"}}"#) == .unavailable)
    }

    @Test func noTokenIsUnauthorized() async {
        let (service, box) = service([], tokens: [nil])
        await #expect(throws: FoodAnalyzeError.unauthorized) { try await service.analyze(.text("x"), locale: "en") }
        #expect(box.requests.isEmpty)
    }
}

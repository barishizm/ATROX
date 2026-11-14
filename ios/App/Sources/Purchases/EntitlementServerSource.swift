import DataKit
import Foundation

/// The server's view of the user's subscription (the `entitlements` table, P090). Only the service role writes it;
/// the owner reads it. Unreachable or missing means "no information", never "not Pro".
protocol EntitlementServerSource: Sendable {
    func fetch() async throws -> ProEntitlement?
}

/// Reads the user's `entitlements` rows over PostgREST (RLS limits them to the owner) and keeps the best one.
struct SupabaseEntitlementSource: EntitlementServerSource {
    struct Row: Decodable, Equatable {
        var productId: String
        var status: String
        var expiresAt: Date?

        enum CodingKeys: String, CodingKey {
            case productId = "product_id", status, expiresAt = "expires_at"
        }
    }

    let configuration: SupabaseConfiguration
    let accessToken: @Sendable () async -> String?
    var session: URLSession = .shared

    func fetch() async throws -> ProEntitlement? {
        guard let token = await accessToken() else { return nil }
        var components = URLComponents(url: configuration.url.appendingPathComponent("rest/v1/entitlements"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "select", value: "product_id,status,expires_at"),
            URLQueryItem(name: "order", value: "expires_at.desc.nullslast"),
            URLQueryItem(name: "limit", value: "10")
        ]
        guard let url = components?.url else { return nil }
        var request = URLRequest(url: url)
        request.setValue(configuration.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: text) { return date }
            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: text) { return date }
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Bad date \(text)"))
        }
        return Self.best(of: try decoder.decode([Row].self, from: data))
    }

    /// Maps the table's status strings (P090 writes them) and picks the row that grants the most.
    static func best(of rows: [Row], now: Date = Date()) -> ProEntitlement? {
        let mapped = rows.map { row in
            ProEntitlement(status: status(for: row.status), productID: row.productId, expiresAt: row.expiresAt, willRenew: row.status == "active" || row.status == "trial")
        }
        return mapped.first { $0.isPro(at: now) } ?? mapped.first
    }

    static func status(for raw: String) -> ProEntitlement.Status {
        switch raw {
        case "active": .active
        case "trial", "trialing": .trial
        case "grace_period", "in_grace_period": .gracePeriod
        case "billing_retry", "in_billing_retry": .billingRetry
        case "refunded", "revoked": .revoked
        default: .expired
        }
    }
}

/// No server (Supabase not configured, tests): StoreKit alone decides.
struct NoEntitlementServer: EntitlementServerSource {
    func fetch() async throws -> ProEntitlement? { nil }
}

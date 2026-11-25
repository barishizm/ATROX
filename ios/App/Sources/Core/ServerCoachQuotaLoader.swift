import CoachKit
import Foundation

/// Reads how many coach messages the signed-in account has left today, straight from the server's own counters
/// (RLS: the caller's own `coach_quota` / `entitlements` rows, public `coach_limits`). The count belongs to the
/// account, so a second device shows the same number without sending a message first.
struct ServerCoachQuotaLoader: Sendable {
    let baseURL: URL
    let anonKey: String
    let accessToken: @Sendable () async -> String?
    var session: URLSession = .shared

    private struct QuotaRow: Decodable { let day: String; let messages: Int }
    private struct EntitlementRow: Decodable { let tier: String; let expires_at: Date?; let status: String? }
    static let proStatuses: Set<String> = ["active", "trial", "grace_period"]

    /// One entitlement row gives Pro now (mirrors `entitlement_tier()`).
    static func grantsPro(tier: String, status: String?, expiresAt: Date?, now: Date) -> Bool {
        tier == "pro" && proStatuses.contains(status ?? "active") && (expiresAt.map { $0 > now } ?? true)
    }

    private struct LimitRow: Decodable { let tier: String; let daily_messages: Int }

    func load(userId: UUID, now: Date = .now, calendar: Calendar = .current) async -> CoachQuota? {
        guard let token = await accessToken() else { return nil }
        let id = userId.uuidString.lowercased()
        async let quota: [QuotaRow]? = fetch("coach_quota", "select=day,messages&user_id=eq.\(id)", token: token)
        async let entitlement: [EntitlementRow]? = fetch("entitlements", "select=tier,expires_at,status&user_id=eq.\(id)", token: token)
        async let limits: [LimitRow]? = fetch("coach_limits", "select=tier,daily_messages", token: token)
        guard let quotaRows = await quota, let entitlementRows = await entitlement, let limitRows = await limits else { return nil }

        // Same rule as the server's entitlement_tier(): a refunded or revoked row is not Pro.
        let isPro = entitlementRows.contains { Self.grantsPro(tier: $0.tier, status: $0.status, expiresAt: $0.expires_at, now: now) }
        let tier: CoachQuota.Tier = isPro ? .pro : .free
        guard let daily = limitRows.first(where: { $0.tier == tier.rawValue })?.daily_messages else { return nil }

        // The server counts per local day of the time zone the app sends; an older day means nothing used today.
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let used = quotaRows.first.flatMap { $0.day == formatter.string(from: now) ? $0.messages : 0 } ?? 0
        let reset = calendar.nextDate(after: now, matching: DateComponents(hour: 0, minute: 0), matchingPolicy: .nextTime)
        return CoachQuota(remaining: max(daily - used, 0), dailyMessages: daily, resetAt: reset, tier: tier)
    }

    private func fetch<T: Decodable>(_ table: String, _ query: String, token: String) async -> [T]? {
        guard let url = URL(string: baseURL.appendingPathComponent("rest/v1/\(table)").absoluteString + "?" + query) else { return nil }
        var request = URLRequest(url: url)
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            guard let date = CoachDates.parse(text) else { throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: text)) }
            return date
        }
        return try? decoder.decode([T].self, from: data)
    }
}

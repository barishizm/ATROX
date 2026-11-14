import Foundation

/// The coach's remaining messages today, sent at the start of every stream.
public struct CoachQuota: Sendable, Equatable {
    public enum Tier: String, Sendable { case free, pro }

    public let remaining: Int
    public let dailyMessages: Int
    public let resetAt: Date?
    public let tier: Tier

    public init(remaining: Int, dailyMessages: Int, resetAt: Date?, tier: Tier) {
        self.remaining = remaining
        self.dailyMessages = dailyMessages
        self.resetAt = resetAt
        self.tier = tier
    }
}

/// One server-sent event of the `coach-chat` stream. Unknown event types decode to nil and are skipped, so a newer
/// server never breaks an older app.
public enum CoachEvent: Sendable, Equatable {
    public enum ToolStatus: String, Sendable { case started, finished }

    case textDelta(String)
    case toolActivity(name: String, status: ToolStatus)
    case proposal(CoachProposal)
    case quota(CoachQuota)
    case usage(promptTokens: Int, cachedTokens: Int, completionTokens: Int)
    case error(code: String, message: String)
    case done(threadId: UUID)

    public static func decode(_ frame: SSEFrame) -> CoachEvent? {
        guard let data = frame.data.data(using: .utf8), let object = try? JSONDecoder().decode(CoachJSON.self, from: data) else {
            return nil
        }
        switch frame.event {
        case "text_delta":
            return object["text"]?.string.map(CoachEvent.textDelta)
        case "tool_activity":
            guard let name = object["name"]?.string, let status = object["status"]?.string.flatMap(ToolStatus.init) else { return nil }
            return .toolActivity(name: name, status: status)
        case "proposal":
            guard let raw = object["proposal"], let proposal = try? decode(CoachProposal.self, from: raw) else { return nil }
            return .proposal(proposal)
        case "quota":
            guard let remaining = object["remaining"]?.int, let daily = object["daily_messages"]?.int else { return nil }
            let tier = object["tier"]?.string.flatMap(CoachQuota.Tier.init) ?? .free
            return .quota(CoachQuota(remaining: remaining, dailyMessages: daily, resetAt: object["reset_at"]?.string.flatMap(CoachDates.parse), tier: tier))
        case "usage":
            return .usage(
                promptTokens: object["prompt_tokens"]?.int ?? 0, cachedTokens: object["cached_tokens"]?.int ?? 0,
                completionTokens: object["completion_tokens"]?.int ?? 0
            )
        case "error":
            return .error(code: object["code"]?.string ?? "internal", message: object["message"]?.string ?? "")
        case "done":
            return object["thread_id"]?.string.flatMap(UUID.init(uuidString:)).map(CoachEvent.done)
        default:
            return nil
        }
    }

    private static func decode<T: Decodable>(_ type: T.Type, from value: CoachJSON) throws -> T {
        try JSONDecoder().decode(type, from: JSONEncoder().encode(value))
    }
}

/// Timestamps as the server writes them (ISO 8601, up to six fractional digits).
public enum CoachDates {
    public static func parse(_ text: String) -> Date? {
        var value = text
        if let dot = value.firstIndex(of: "."), let zone = value[dot...].firstIndex(where: { $0 == "+" || $0 == "-" || $0 == "Z" }) {
            let fraction = value[value.index(after: dot)..<zone].prefix(3)
            value = String(value[..<dot]) + "." + fraction + String(value[zone...])
        }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) { return date }
        return ISO8601DateFormatter().date(from: value)
    }

    public static func format(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}

import Foundation

/// `SocialService` over the P085 security definer functions (`/rest/v1/rpc/...`) with the user's session token.
/// Every function checks `auth.uid()` itself, so nothing here can act for someone else.
public struct SupabaseSocialService: SocialService {
    public typealias Fetch = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    private let baseURL: URL
    private let anonKey: String
    private let accessToken: SupabaseRemoteStore.AccessToken
    private let fetch: Fetch

    public init(configuration: SupabaseConfiguration, accessToken: @escaping SupabaseRemoteStore.AccessToken, session: URLSession = .shared) {
        self.init(baseURL: configuration.url, anonKey: configuration.anonKey, accessToken: accessToken) { try await session.data(for: $0) }
    }

    init(baseURL: URL, anonKey: String, accessToken: @escaping SupabaseRemoteStore.AccessToken, fetch: @escaping Fetch) {
        self.baseURL = baseURL
        self.anonKey = anonKey
        self.accessToken = accessToken
        self.fetch = fetch
    }

    public func myProfile() async throws -> SocialProfile? {
        // RLS lets the owner read their own row; an empty array means social is off.
        var components = URLComponents(url: baseURL.appendingPathComponent("rest/v1/public_profiles"), resolvingAgainstBaseURL: false)
        let me = try await currentUserID()
        components?.queryItems = [
            URLQueryItem(name: "select", value: "username,display_name,avatar_emoji,avatar_color,is_discoverable,share_score"),
            URLQueryItem(name: "user_id", value: "eq.\(me.uuidString.lowercased())")
        ]
        guard let url = components?.url else { throw SocialError.failed }
        let data = try await perform(try await request("GET", url: url, body: nil))
        return try Self.decode([ProfileRow].self, data).first?.profile
    }

    public func usernameAvailable(_ username: String) async throws -> Bool {
        let data = try await rpc("username_available", ["p_username": SocialTextPolicy.canonical(username)])
        return (try? JSONDecoder().decode(Bool.self, from: data)) ?? false
    }

    public func saveProfile(_ profile: SocialProfile) async throws -> SocialProfile {
        let body: [String: Any] = [
            "p_username": SocialTextPolicy.canonical(profile.username),
            "p_display_name": profile.displayName.trimmingCharacters(in: .whitespacesAndNewlines),
            "p_avatar_emoji": profile.avatarEmoji,
            "p_avatar_color": profile.avatarColor.rawValue,
            "p_is_discoverable": profile.isDiscoverable,
            "p_share_score": profile.sharesScore
        ]
        let data = try await rpc("upsert_my_profile", body)
        guard let row = try? JSONDecoder().decode(ProfileRow.self, from: data) else { throw SocialError.failed }
        return row.profile
    }

    public func deleteProfile() async throws { _ = try await rpc("delete_my_profile", [:]) }

    public func search(_ query: String) async throws -> [SocialPerson] {
        try Self.decode([PersonRow].self, try await rpc("search_users", ["p_query": SocialTextPolicy.canonical(query)])).map(\.person)
    }

    public func resolveInvite(_ username: String) async throws -> SocialPerson? {
        let data = try await rpc("resolve_invite", ["p_username": SocialTextPolicy.canonical(username)])
        return try Self.decode([PersonRow].self, data).first?.person
    }

    public func connections() async throws -> [SocialPerson] {
        try Self.decode([PersonRow].self, try await rpc("list_social", [:])).map(\.person)
    }

    @discardableResult
    public func sendRequest(to userId: UUID) async throws -> SocialRelation {
        let data = try await rpc("send_request", ["p_addressee": Self.id(userId)])
        let value = (try? JSONDecoder().decode(String.self, from: data)) ?? ""
        return SocialRelation(rawValue: value) ?? .outgoing
    }

    public func respond(to userId: UUID, accept: Bool) async throws {
        _ = try await rpc("respond_request", ["p_requester": Self.id(userId), "p_accept": accept])
    }

    public func removeFriend(_ userId: UUID) async throws { _ = try await rpc("remove_friend", ["p_other": Self.id(userId)]) }
    public func block(_ userId: UUID) async throws { _ = try await rpc("block_user", ["p_other": Self.id(userId)]) }
    public func unblock(_ userId: UUID) async throws { _ = try await rpc("unblock_user", ["p_other": Self.id(userId)]) }

    public func report(_ userId: UUID, reason: ReportReason, note: String?) async throws {
        var body: [String: Any] = ["p_reported": Self.id(userId), "p_reason": reason.rawValue]
        if let note, !note.isEmpty { body["p_note"] = note }
        _ = try await rpc("report_user", body)
    }

    public func ranking(_ period: RankingPeriod) async throws -> [RankingEntry] {
        try Self.decode([RankRow].self, try await rpc("friends_leaderboard", ["p_period": period.rawValue])).map(\.entry)
    }

    @discardableResult
    public func publishScore(_ publication: ScorePublication) async throws -> Bool {
        let body: [String: Any] = [
            "overall_score": publication.score, "provisional": publication.isProvisional, "weekly_workouts": publication.weeklyWorkouts
        ]
        let url = baseURL.appendingPathComponent("functions/v1/publish-score")
        let data = try await perform(try await request("POST", url: url, body: try JSONSerialization.data(withJSONObject: body)))
        return (try? JSONDecoder().decode(PublishResult.self, from: data))?.published ?? false
    }

    // MARK: Wire rows

    private struct PublishResult: Decodable { let published: Bool }

    private struct RankRow: Decodable {
        let rank: Int
        let userId: UUID
        let username: String
        let displayName: String
        let avatarEmoji: String
        let avatarColor: String
        let value: Int?
        let provisional: Bool?
        let isMe: Bool

        enum CodingKeys: String, CodingKey {
            case rank, userId = "user_id", username, displayName = "display_name", avatarEmoji = "avatar_emoji"
            case avatarColor = "avatar_color", value, provisional, isMe = "is_me"
        }

        var entry: RankingEntry {
            RankingEntry(
                id: userId, rank: rank, username: username, displayName: displayName, avatarEmoji: avatarEmoji,
                avatarColor: AvatarColor(rawValue: avatarColor) ?? .ember, value: value, isProvisional: provisional ?? false, isMe: isMe
            )
        }
    }

    private struct ProfileRow: Decodable {
        let username: String
        let displayName: String
        let avatarEmoji: String
        let avatarColor: String
        let isDiscoverable: Bool
        let shareScore: Bool

        enum CodingKeys: String, CodingKey {
            case username, displayName = "display_name", avatarEmoji = "avatar_emoji", avatarColor = "avatar_color"
            case isDiscoverable = "is_discoverable", shareScore = "share_score"
        }

        var profile: SocialProfile {
            SocialProfile(
                username: username, displayName: displayName, avatarEmoji: avatarEmoji,
                avatarColor: AvatarColor(rawValue: avatarColor) ?? .ember, isDiscoverable: isDiscoverable, sharesScore: shareScore
            )
        }
    }

    private struct PersonRow: Decodable {
        let userId: UUID
        let username: String
        let displayName: String
        let avatarEmoji: String
        let avatarColor: String
        let relation: String
        let score: Int?
        let provisional: Bool?
        let weekly: Int?

        enum CodingKeys: String, CodingKey {
            case userId = "user_id", username, displayName = "display_name", avatarEmoji = "avatar_emoji"
            case avatarColor = "avatar_color", relation, score = "shared_overall_score"
            case provisional = "shared_score_provisional", weekly = "weekly_workouts"
        }

        var person: SocialPerson {
            SocialPerson(
                id: userId, username: username, displayName: displayName, avatarEmoji: avatarEmoji,
                avatarColor: AvatarColor(rawValue: avatarColor) ?? .ember, relation: SocialRelation(rawValue: relation) ?? .none,
                score: score, scoreIsProvisional: provisional ?? false, weeklyWorkouts: weekly
            )
        }
    }

    // MARK: HTTP

    private static func id(_ uuid: UUID) -> String { uuid.uuidString.lowercased() }

    private static func decode<T: Decodable>(_ type: T.Type, _ data: Data) throws -> T {
        do { return try JSONDecoder().decode(type, from: data) } catch { throw SocialError.failed }
    }

    private func currentUserID() async throws -> UUID {
        guard let token = await accessToken(), let id = Self.subject(of: token) else { throw SocialError.unauthorized }
        return id
    }

    /// The `sub` claim of the session JWT (the signed-in user's id).
    static func subject(of jwt: String) -> UUID? {
        let parts = jwt.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var base64 = parts[1].replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64 += "=" }
        guard let data = Data(base64Encoded: base64),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sub = object["sub"] as? String else { return nil }
        return UUID(uuidString: sub)
    }

    private func rpc(_ function: String, _ arguments: [String: Any]) async throws -> Data {
        let body = try JSONSerialization.data(withJSONObject: arguments)
        let url = baseURL.appendingPathComponent("rest/v1/rpc/\(function)")
        return try await perform(try await request("POST", url: url, body: body))
    }

    private func request(_ method: String, url: URL, body: Data?) async throws -> URLRequest {
        guard let token = await accessToken() else { throw SocialError.unauthorized }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 20
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        return request
    }

    private func perform(_ request: URLRequest) async throws -> Data {
        let data: Data
        let response: URLResponse
        do { (data, response) = try await fetch(request) } catch { throw SocialError.failed }
        guard let http = response as? HTTPURLResponse else { throw SocialError.failed }
        guard (200..<300).contains(http.statusCode) else { throw Self.error(status: http.statusCode, body: data) }
        return data
    }

    /// PostgREST puts the `raise exception` text in `message`.
    static func error(status: Int, body: Data) -> SocialError {
        let message = (try? JSONSerialization.jsonObject(with: body) as? [String: Any])?["message"] as? String ?? ""
        switch message {
        case "invalid_username": return .invalidUsername
        case "invalid_display_name": return .invalidDisplayName
        case "username_taken": return .usernameTaken
        case "rate_limited": return .rateLimited
        case "blocked": return .blocked
        case "profile_required": return .profileRequired
        case "no_such_request": return .notFound
        default: break
        }
        switch status {
        case 401, 403: return .unauthorized
        case 404: return .notFound
        case 429: return .rateLimited
        default: return .failed
        }
    }
}

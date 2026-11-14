import Foundation

/// How another user relates to me (P085 `social_person.relation`).
public enum SocialRelation: String, Codable, Sendable, Equatable {
    case none, friend, incoming, outgoing, blocked
}

public enum AvatarColor: String, CaseIterable, Codable, Sendable {
    case ember, sky, mint, violet, gold, rose, slate
}

/// The user's own public profile and sharing choices. Both switches default to off and are explicit user choices.
public struct SocialProfile: Equatable, Sendable {
    public var username: String
    public var displayName: String
    public var avatarEmoji: String
    public var avatarColor: AvatarColor
    public var isDiscoverable: Bool
    public var sharesScore: Bool

    public init(
        username: String, displayName: String, avatarEmoji: String = "💪", avatarColor: AvatarColor = .ember,
        isDiscoverable: Bool = false, sharesScore: Bool = false
    ) {
        self.username = username
        self.displayName = displayName
        self.avatarEmoji = avatarEmoji
        self.avatarColor = avatarColor
        self.isDiscoverable = isDiscoverable
        self.sharesScore = sharesScore
    }
}

/// Someone else, as returned by search and the friends list. Scores appear only for friends who share them.
public struct SocialPerson: Hashable, Identifiable, Sendable {
    public var id: UUID
    public var username: String
    public var displayName: String
    public var avatarEmoji: String
    public var avatarColor: AvatarColor
    public var relation: SocialRelation
    public var score: Int?
    public var scoreIsProvisional: Bool
    public var weeklyWorkouts: Int?

    public init(
        id: UUID, username: String, displayName: String, avatarEmoji: String = "💪", avatarColor: AvatarColor = .ember,
        relation: SocialRelation, score: Int? = nil, scoreIsProvisional: Bool = false, weeklyWorkouts: Int? = nil
    ) {
        self.id = id
        self.username = username
        self.displayName = displayName
        self.avatarEmoji = avatarEmoji
        self.avatarColor = avatarColor
        self.relation = relation
        self.score = score
        self.scoreIsProvisional = scoreIsProvisional
        self.weeklyWorkouts = weeklyWorkouts
    }
}

public enum ReportReason: String, CaseIterable, Sendable {
    case inappropriateName = "inappropriate_name"
    case harassment, spam
    case fakeScore = "fake_score"
    case other
}

public enum SocialError: Error, Equatable, Sendable {
    case invalidUsername
    case invalidDisplayName
    case usernameTaken
    case rateLimited
    case blocked
    case profileRequired
    case notFound
    case unauthorized
    case failed
}

/// Ranking tabs (P087). Values are scores, workouts this week, and score change this month.
public enum RankingPeriod: String, CaseIterable, Sendable {
    case score, weekly, month
}

/// One row of the friends ranking. Only the published score, workout count or change: never body weight or lifts.
public struct RankingEntry: Identifiable, Hashable, Sendable {
    public var id: UUID
    public var rank: Int
    public var username: String
    public var displayName: String
    public var avatarEmoji: String
    public var avatarColor: AvatarColor
    /// nil when the person does not share a value for this tab.
    public var value: Int?
    public var isProvisional: Bool
    public var isMe: Bool

    public init(
        id: UUID, rank: Int, username: String, displayName: String, avatarEmoji: String = "💪", avatarColor: AvatarColor = .ember,
        value: Int?, isProvisional: Bool = false, isMe: Bool = false
    ) {
        self.id = id
        self.rank = rank
        self.username = username
        self.displayName = displayName
        self.avatarEmoji = avatarEmoji
        self.avatarColor = avatarColor
        self.value = value
        self.isProvisional = isProvisional
        self.isMe = isMe
    }

    /// Competition ranking (1, 1, 3): equal values share a rank, rows without a value come last, names break display ties.
    public static func ranked(_ entries: [RankingEntry]) -> [RankingEntry] {
        let sorted = entries.sorted {
            switch ($0.value, $1.value) {
            case let (lhs?, rhs?) where lhs != rhs: return lhs > rhs
            case (nil, _?): return false
            case (_?, nil): return true
            default: return $0.username < $1.username
            }
        }
        var result: [RankingEntry] = []
        for (index, var entry) in sorted.enumerated() {
            if index > 0, sorted[index - 1].value == entry.value { entry.rank = result[index - 1].rank } else { entry.rank = index + 1 }
            result.append(entry)
        }
        return result
    }
}

/// What the app tells `publish-score`; the server decides whether it is stored.
public struct ScorePublication: Equatable, Sendable {
    public var score: Int
    public var isProvisional: Bool
    public var weeklyWorkouts: Int

    public init(score: Int, isProvisional: Bool, weeklyWorkouts: Int) {
        self.score = score
        self.isProvisional = isProvisional
        self.weeklyWorkouts = weeklyWorkouts
    }
}

/// Friends, requests, blocks and reports. Production: `SupabaseSocialService` (P085 security definer functions);
/// tests and builds without a server use `FakeSocialService`.
public protocol SocialService: Sendable {
    /// The caller's own profile; nil while social is off.
    func myProfile() async throws -> SocialProfile?
    func usernameAvailable(_ username: String) async throws -> Bool
    func saveProfile(_ profile: SocialProfile) async throws -> SocialProfile
    /// "Turn social off": removes the profile and every friendship, request and block.
    func deleteProfile() async throws
    func search(_ query: String) async throws -> [SocialPerson]
    /// The person an invite link names (P088): an exact username, found even when they are hidden from search.
    func resolveInvite(_ username: String) async throws -> SocialPerson?
    /// Friends, incoming and outgoing requests and my blocks.
    func connections() async throws -> [SocialPerson]
    @discardableResult func sendRequest(to userId: UUID) async throws -> SocialRelation
    func respond(to userId: UUID, accept: Bool) async throws
    func removeFriend(_ userId: UUID) async throws
    func block(_ userId: UUID) async throws
    func unblock(_ userId: UUID) async throws
    func report(_ userId: UUID, reason: ReportReason, note: String?) async throws
    /// Me and my friends ranked for a tab (P087).
    func ranking(_ period: RankingPeriod) async throws -> [RankingEntry]
    /// Sends my score to `publish-score`. True when the server stored it (false: sharing is off or the values were rejected).
    @discardableResult func publishScore(_ publication: ScorePublication) async throws -> Bool
}

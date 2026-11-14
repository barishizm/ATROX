import Foundation

/// In-memory social backend for tests, previews and `-uitest-fake-social`.
public actor FakeSocialService: SocialService {
    private var profile: SocialProfile?
    private var people: [UUID: SocialPerson]
    private let takenUsernames: Set<String>
    public private(set) var reports: [(userId: UUID, reason: ReportReason, note: String?)] = []
    private var failure: SocialError?
    private var published: ScorePublication?
    public private(set) var publishCount = 0

    public init(profile: SocialProfile? = nil, people: [SocialPerson] = [], takenUsernames: Set<String> = []) {
        self.profile = profile
        self.people = Dictionary(uniqueKeysWithValues: people.map { ($0.id, $0) })
        self.takenUsernames = takenUsernames
    }

    /// Makes every following call throw `error` (nil restores normal behaviour).
    public func setFailure(_ error: SocialError?) { failure = error }

    public func myProfile() async throws -> SocialProfile? {
        try check()
        return profile
    }

    public func usernameAvailable(_ username: String) async throws -> Bool {
        try check()
        let name = SocialTextPolicy.canonical(username)
        return SocialTextPolicy.usernameIssue(name) == nil && !takenUsernames.contains(name)
            && !people.values.contains { $0.username == name }
    }

    public func saveProfile(_ new: SocialProfile) async throws -> SocialProfile {
        try check()
        var saved = new
        saved.username = SocialTextPolicy.canonical(new.username)
        saved.displayName = new.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard SocialTextPolicy.usernameIssue(saved.username) == nil else { throw SocialError.invalidUsername }
        guard SocialTextPolicy.isDisplayNameValid(saved.displayName) else { throw SocialError.invalidDisplayName }
        if saved.username != profile?.username, !(try await usernameAvailable(saved.username)) { throw SocialError.usernameTaken }
        profile = saved
        return saved
    }

    public func deleteProfile() async throws {
        try check()
        profile = nil
        people = people.filter { $0.value.relation == .none }
    }

    public func search(_ query: String) async throws -> [SocialPerson] {
        try check()
        let prefix = SocialTextPolicy.canonical(query)
        guard prefix.count >= 2, profile != nil else { return [] }
        return people.values.filter { $0.username.hasPrefix(prefix) && $0.relation != .blocked }
            .sorted { $0.username < $1.username }
    }

    public func resolveInvite(_ username: String) async throws -> SocialPerson? {
        try check()
        let name = SocialTextPolicy.canonical(username)
        guard profile != nil, name != profile?.username else { return nil }
        return people.values.first { $0.username == name && $0.relation != .blocked }
    }

    public func connections() async throws -> [SocialPerson] {
        try check()
        return people.values.filter { $0.relation != .none }.sorted { $0.username < $1.username }
    }

    @discardableResult
    public func sendRequest(to userId: UUID) async throws -> SocialRelation {
        try check()
        guard var person = people[userId] else { throw SocialError.notFound }
        switch person.relation {
        case .blocked: throw SocialError.blocked
        case .friend, .outgoing: return person.relation
        case .incoming, .none:
            person.relation = person.relation == .incoming ? .friend : .outgoing
            people[userId] = person
            return person.relation
        }
    }

    public func respond(to userId: UUID, accept: Bool) async throws {
        try check()
        guard var person = people[userId], person.relation == .incoming else { throw SocialError.notFound }
        person.relation = accept ? .friend : .none
        people[userId] = person
    }

    public func removeFriend(_ userId: UUID) async throws {
        try check()
        guard var person = people[userId], person.relation != .blocked else { return }
        person.relation = .none
        people[userId] = person
    }

    public func block(_ userId: UUID) async throws {
        try check()
        guard var person = people[userId] else { throw SocialError.notFound }
        person.relation = .blocked
        person.score = nil
        people[userId] = person
    }

    public func unblock(_ userId: UUID) async throws {
        try check()
        guard var person = people[userId], person.relation == .blocked else { return }
        person.relation = .none
        people[userId] = person
    }

    public func report(_ userId: UUID, reason: ReportReason, note: String?) async throws {
        try check()
        reports.append((userId, reason, note))
    }

    public func ranking(_ period: RankingPeriod) async throws -> [RankingEntry] {
        try check()
        guard let profile else { return [] }
        var entries: [RankingEntry] = []
        let mine: Int? = switch period {
        case .score: profile.sharesScore ? published?.score : nil
        case .weekly: published?.weeklyWorkouts
        case .month: profile.sharesScore && published != nil ? 0 : nil
        }
        entries.append(RankingEntry(
            id: Self.meID, rank: 0, username: profile.username, displayName: profile.displayName, avatarEmoji: profile.avatarEmoji,
            avatarColor: profile.avatarColor, value: mine, isProvisional: period == .score && published?.isProvisional == true, isMe: true
        ))
        for person in people.values where person.relation == .friend {
            let value: Int? = switch period {
            case .score: person.score
            case .weekly: person.weeklyWorkouts
            case .month: person.score == nil ? nil : 0
            }
            entries.append(RankingEntry(
                id: person.id, rank: 0, username: person.username, displayName: person.displayName, avatarEmoji: person.avatarEmoji,
                avatarColor: person.avatarColor, value: value, isProvisional: period == .score && person.scoreIsProvisional
            ))
        }
        return RankingEntry.ranked(entries)
    }

    @discardableResult
    public func publishScore(_ publication: ScorePublication) async throws -> Bool {
        try check()
        publishCount += 1
        // Like the server: with no profile or sharing off nothing is stored.
        guard let profile, profile.sharesScore else { return false }
        published = publication
        return true
    }

    /// The id the fake uses for the signed-in user's own ranking row.
    public static let meID = UUID(uuidString: "00000000-0000-0000-0000-00000000000E")!

    private func check() throws {
        if let failure { throw failure }
    }
}

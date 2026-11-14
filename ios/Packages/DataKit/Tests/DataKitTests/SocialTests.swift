import Foundation
import Testing

@testable import DataKit

@Suite struct SocialTextPolicyTests {
    @Test func acceptsPlainUsernames() {
        #expect(SocialTextPolicy.usernameIssue("Iron_Mike") == nil)
        #expect(SocialTextPolicy.canonical("  Iron_Mike ") == "iron_mike")
    }

    @Test func rejectsBadShapes() {
        #expect(SocialTextPolicy.usernameIssue("ab") == .tooShort)
        #expect(SocialTextPolicy.usernameIssue(String(repeating: "a", count: 21)) == .tooLong)
        #expect(SocialTextPolicy.usernameIssue("no spaces") == .invalidCharacters)
        #expect(SocialTextPolicy.usernameIssue("çağrı") == .invalidCharacters)
        #expect(SocialTextPolicy.usernameIssue("Admin") == .reserved)
    }

    @Test func blocklistSeesThroughDisguises() {
        #expect(SocialTextPolicy.usernameIssue("f_u_c_k") == .inappropriate)
        #expect(SocialTextPolicy.usernameIssue("s1kt1r") == .inappropriate)
        #expect(!SocialTextPolicy.isDisplayNameValid("SİKTİR"))
        #expect(!SocialTextPolicy.isDisplayNameValid("AMK"))
        #expect(SocialTextPolicy.isDisplayNameValid("Ayşe Yılmaz"))
        #expect(SocialTextPolicy.isDisplayNameValid("Amanda"))
        #expect(!SocialTextPolicy.isDisplayNameValid("   "))
    }
}

@Suite struct SupabaseSocialServiceTests {
    private func service(status: Int = 200, body: String, record: Recorder = Recorder()) -> SupabaseSocialService {
        SupabaseSocialService(baseURL: URL(string: "https://x.test")!, anonKey: "anon", accessToken: { "tok" }) { request in
            record.requests.withLock { $0.append(request) }
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            return (Data(body.utf8), response)
        }
    }

    @Test func searchDecodesPeople() async throws {
        let id = UUID()
        let body = """
        [{"user_id":"\(id.uuidString.lowercased())","username":"alice","display_name":"Alice","avatar_emoji":"🔥",\
        "avatar_color":"sky","relation":"none","shared_overall_score":null,"shared_score_provisional":false,"weekly_workouts":null}]
        """
        let recorder = Recorder()
        let people = try await service(body: body, record: recorder).search(" Ali ")
        #expect(people.map(\.username) == ["alice"])
        #expect(people.first?.avatarColor == .sky)
        let request = recorder.requests.withLock { $0.first }
        #expect(request?.url?.path == "/rest/v1/rpc/search_users")
        #expect(String(data: request?.httpBody ?? Data(), encoding: .utf8)?.contains("\"ali\"") == true)
    }

    @Test func mapsServerErrors() async {
        let taken = service(status: 400, body: #"{"message":"username_taken","code":"23505"}"#)
        await #expect(throws: SocialError.usernameTaken) {
            _ = try await taken.saveProfile(SocialProfile(username: "alice", displayName: "A"))
        }
        let limited = service(status: 400, body: #"{"message":"rate_limited"}"#)
        await #expect(throws: SocialError.rateLimited) { _ = try await limited.search("ali") }
    }

    @Test func readsUserIDFromJWT() {
        let id = UUID()
        let payload = Data(#"{"sub":"\#(id.uuidString.lowercased())"}"#.utf8).base64EncodedString()
            .replacingOccurrences(of: "=", with: "")
        #expect(SupabaseSocialService.subject(of: "h.\(payload).s") == id)
        #expect(SupabaseSocialService.subject(of: "garbage") == nil)
    }
}

@Suite struct RankingTests {
    private func entry(_ name: String, _ value: Int?) -> RankingEntry {
        RankingEntry(id: UUID(), rank: 0, username: name, displayName: name, value: value)
    }

    @Test func ranksHighestFirstWithSharedRanksOnTies() {
        let ranked = RankingEntry.ranked([entry("c", 50), entry("a", 70), entry("b", 70), entry("d", nil)])
        #expect(ranked.map(\.username) == ["a", "b", "c", "d"])
        #expect(ranked.map(\.rank) == [1, 1, 3, 4])
    }

    @Test func rowsWithoutAValueShareTheLastRank() {
        let ranked = RankingEntry.ranked([entry("a", nil), entry("b", nil), entry("c", 10)])
        #expect(ranked.map(\.rank) == [1, 2, 2])
    }

    @Test func decodesRankingAndPublishResult() async throws {
        let id = UUID()
        let body = """
        [{"rank":1,"user_id":"\(id.uuidString.lowercased())","username":"alice","display_name":"Alice","avatar_emoji":"🔥",\
        "avatar_color":"sky","value":61,"provisional":true,"is_me":true}]
        """
        let recorder = Recorder()
        let rows = try await SupabaseSocialService(baseURL: URL(string: "https://x.test")!, anonKey: "a", accessToken: { "t" }) { request in
            recorder.requests.withLock { $0.append(request) }
            return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }.ranking(.month)
        #expect(rows.first?.value == 61 && rows.first?.isProvisional == true && rows.first?.isMe == true)
        #expect(recorder.requests.withLock { $0.first?.url?.path } == "/rest/v1/rpc/friends_leaderboard")

        let published = SupabaseSocialService(baseURL: URL(string: "https://x.test")!, anonKey: "a", accessToken: { "t" }) { request in
            #expect(request.url?.path == "/functions/v1/publish-score")
            return (Data(#"{"published":false,"reason":"sharing_off"}"#.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        #expect(try await published.publishScore(ScorePublication(score: 60, isProvisional: false, weeklyWorkouts: 2)) == false)
    }

    @Test func fakePublishesOnlyWhileSharing() async throws {
        let off = FakeSocialService(profile: SocialProfile(username: "me", displayName: "Me"))
        #expect(try await off.publishScore(ScorePublication(score: 60, isProvisional: false, weeklyWorkouts: 2)) == false)
        #expect(try await off.ranking(.score).first?.value == nil)
        let on = FakeSocialService(profile: SocialProfile(username: "me", displayName: "Me", sharesScore: true))
        #expect(try await on.publishScore(ScorePublication(score: 60, isProvisional: false, weeklyWorkouts: 2)) == true)
        #expect(try await on.ranking(.score).first?.value == 60)
    }
}

@Suite struct FakeSocialServiceTests {
    @Test func requestFlowAndBlock() async throws {
        let bob = SocialPerson(id: UUID(), username: "bob", displayName: "Bob", relation: .none)
        let service = FakeSocialService(profile: SocialProfile(username: "me", displayName: "Me"), people: [bob])
        #expect(try await service.sendRequest(to: bob.id) == .outgoing)
        try await service.block(bob.id)
        #expect(try await service.search("bo").isEmpty)
        await #expect(throws: SocialError.blocked) { try await service.sendRequest(to: bob.id) }
        try await service.unblock(bob.id)
        #expect(try await service.connections().isEmpty)
    }
}

final class Recorder: @unchecked Sendable {
    let requests = Lock<[URLRequest]>([])
}

struct Lock<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private let box: Box
    final class Box { var value: Value; init(_ value: Value) { self.value = value } }
    init(_ value: Value) { box = Box(value) }
    func withLock<T>(_ body: (inout Value) -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body(&box.value)
    }
}

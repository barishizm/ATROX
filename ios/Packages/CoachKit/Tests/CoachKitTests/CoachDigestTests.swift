import Foundation
import Testing
@testable import CoachKit

@Suite struct CoachDigestTests {
    private let workout = WorkoutDigest(
        durationMin: 52, sets: 18, volumeKg: 6400,
        exercises: [.init(name: "Bench Press", sets: 4, topSet: "100 kg x 5")],
        records: [DigestRecord(exercise: "Bench Press", kind: "e1rm")],
        previous: .init(sets: 16, volumeKg: 5900, durationMin: 50)
    )

    private func service(_ replies: [(Int, String)], tokens: [String?] = ["old", "fresh"]) -> (SupabaseCoachDigestService, Box) {
        let box = Box(replies)
        let token = TokenBox(tokens)
        let service = SupabaseCoachDigestService(
            baseURL: URL(string: "https://example.test")!, anonKey: "anon", accessToken: { token.next() }, refreshedToken: { token.next() },
            send: { request in
                box.requests.append(request)
                let (status, body) = box.nextReply()
                let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
                return (Data(body.utf8), response)
            }
        )
        return (service, box)
    }

    private final class Box: @unchecked Sendable {
        private let lock = NSLock()
        private var replies: [(Int, String)]
        private var sent: [URLRequest] = []
        init(_ replies: [(Int, String)]) { self.replies = replies }
        var requests: [URLRequest] {
            get { lock.withLock { sent } }
            set { lock.withLock { sent = newValue } }
        }
        func nextReply() -> (Int, String) { lock.withLock { replies.isEmpty ? (500, "{}") : replies.removeFirst() } }
    }

    private final class TokenBox: @unchecked Sendable {
        private let lock = NSLock()
        private var values: [String?]
        init(_ values: [String?]) { self.values = values }
        func next() -> String? { lock.withLock { values.isEmpty ? nil : values.removeFirst() } }
    }

    @Test func theWorkoutBodyMatchesTheServerSchema() throws {
        let body = CoachDigestRequest(.workout(workout), locale: "en", timeZone: "Europe/Istanbul").jsonBody
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["kind"] as? String == "workout" && json["locale"] as? String == "en" && json["time_zone"] as? String == "Europe/Istanbul")
        let inner = try #require(json["workout"] as? [String: Any])
        #expect(inner["duration_min"] as? Int == 52 && inner["volume_kg"] as? Double == 6400 && inner["previous"] == nil)
        let exercise = try #require((inner["exercises"] as? [[String: Any]])?.first)
        #expect(exercise["top_set"] as? String == "100 kg x 5")
        #expect((json["previous"] as? [String: Any])?["volume_kg"] as? Double == 5900)
        #expect(json["week"] == nil)
    }

    @Test func theWeeklyBodyCarriesOnlyTheWeek() throws {
        let week = WeeklyDigest(
            workouts: 3, goal: 4, totalSets: 52, volumeChangePct: 8, records: [], overallScore: 61, overallChange: 2,
            topGroup: "chest", neglectedGroups: ["legs"]
        )
        let json = try #require(try JSONSerialization.jsonObject(with: CoachDigestRequest(.weekly(week), locale: "tr").jsonBody) as? [String: Any])
        #expect(json["kind"] as? String == "weekly" && json["workout"] == nil && json["previous"] == nil)
        let inner = try #require(json["week"] as? [String: Any])
        #expect(inner["total_sets"] as? Int == 52 && inner["neglected_groups"] as? [String] == ["legs"] && inner["overall_change"] as? Double == 2)
    }

    @Test func aSuccessfulReplyIsReturnedAndTheRequestIsAuthorised() async throws {
        let (service, box) = service([(200, #"{"text":"Strong session.","cached":false,"kind":"workout"}"#)])
        let text = try await service.comment(for: CoachDigestRequest(.workout(workout), locale: "en"))
        #expect(text == "Strong session.")
        let sent = try #require(box.requests.first)
        #expect(sent.url?.path == "/functions/v1/coach-digest" && sent.value(forHTTPHeaderField: "Authorization") == "Bearer old")
    }

    @Test func aFreeUserGetsAnErrorTheCallerCanHide() async {
        let (service, _) = service([(403, #"{"error":{"code":"pro_required","message":"x"}}"#)])
        await #expect(throws: CoachError.server(code: "pro_required", message: "x")) {
            try await service.comment(for: CoachDigestRequest(.workout(workout), locale: "en"))
        }
    }

    @Test func anExpiredTokenIsRefreshedOnce() async throws {
        let (service, box) = service([(401, #"{"error":{"code":"unauthorized","message":"x"}}"#), (200, #"{"text":"ok then"}"#)])
        #expect(try await service.comment(for: CoachDigestRequest(.workout(workout), locale: "en")) == "ok then")
        #expect(box.requests.map { $0.value(forHTTPHeaderField: "Authorization") } == ["Bearer old", "Bearer fresh"])
    }

    @Test func noTokenMeansNoRequest() async {
        let (service, box) = service([], tokens: [nil])
        await #expect(throws: CoachError.unauthorized) { try await service.comment(for: CoachDigestRequest(.workout(workout), locale: "en")) }
        #expect(box.requests.isEmpty)
    }

    @Test func anEmptyTextIsAnInvalidResponse() async {
        let (service, _) = service([(200, #"{"text":"  "}"#)])
        await #expect(throws: CoachError.invalidResponse) { try await service.comment(for: CoachDigestRequest(.workout(workout), locale: "en")) }
    }
}

@Suite struct OnDeviceCommentTests {
    private let digest = WorkoutDigest(
        durationMin: 45, sets: 15, volumeKg: 5200.4, exercises: [.init(name: "Squat", sets: 5, topSet: "80 kg x 5")],
        records: [DigestRecord(exercise: "Squat", kind: "weight")], previous: .init(sets: 14, volumeKg: 4900, durationMin: 44)
    )

    @Test func thePromptHoldsOnlySummaryFacts() {
        let prompt = OnDeviceComment.prompt(for: digest)
        #expect(prompt.contains("45 min") && prompt.contains("15 working sets") && prompt.contains("5200 kg"))
        #expect(prompt.contains("Squat (5 sets, top 80 kg x 5)") && prompt.contains("previous similar workout: 14 sets"))
        #expect(prompt.contains("records: Squat (weight)"))
    }

    @Test func theInstructionsForbidMedicalAndInventedContent() {
        #expect(OnDeviceComment.instructions.contains("No medical"))
        #expect(OnDeviceComment.instructions.contains("Never invent numbers"))
    }

    @Test func plainShortAnswersPass() {
        #expect(OnDeviceComment.sanitize("**Solid session.** Volume is up from last time. Add one rep to your top set.") == "Solid session. Volume is up from last time. Add one rep to your top set.")
    }

    @Test func medicalDietAndRamblingAnswersAreDropped() {
        #expect(OnDeviceComment.sanitize("Great work! Take creatine to recover faster.") == nil)
        #expect(OnDeviceComment.sanitize("That knee pain sounds like an injury, see a doctor.") == nil)
        #expect(OnDeviceComment.sanitize("One. Two. Three. Four. Five sentences here.") == nil)
        #expect(OnDeviceComment.sanitize("ok") == nil)
        #expect(OnDeviceComment.sanitize(String(repeating: "Strong work today. ", count: 40)) == nil)
    }

    @Test func turkishIsOffUntilItHasBeenJudged() {
        #expect(OnDeviceComment.isEnabled(language: "en"))
        #expect(!OnDeviceComment.isEnabled(language: "tr"))
        #expect(!OnDeviceComment.isAvailable(language: "tr"))
    }
}

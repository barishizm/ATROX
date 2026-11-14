import CoachKit
import DataKit
import Foundation
import Testing

@testable import ATROX

@Suite struct CoachCommentProviderTests {
    private final class FakeDigest: CoachDigestService, @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        let result: Result<String, CoachError>
        init(_ result: Result<String, CoachError>) { self.result = result }
        var calls: Int { lock.withLock { count } }
        func comment(for request: CoachDigestRequest) async throws -> String {
            lock.withLock { count += 1 }
            return try result.get()
        }
    }

    private let workout = WorkoutDigest(durationMin: 50, sets: 16, volumeKg: 5000, exercises: [], records: [])
    private let week = WeeklyDigest(
        workouts: 3, goal: 4, totalSets: 40, volumeChangePct: 5, records: [], overallScore: 60, overallChange: 1, topGroup: "chest", neglectedGroups: []
    )

    private func provider(
        _ digest: FakeDigest?, consent: Bool = true, enabled: Bool = true, onDevice: String? = nil
    ) -> CoachCommentProvider {
        CoachCommentProvider(
            digest: digest, consentGranted: { consent }, proactiveEnabled: { enabled },
            onDeviceAvailable: { _ in onDevice != nil }, onDevice: { _, _ in onDevice }
        )
    }

    @Test func aProUserGetsTheServerComment() async {
        let digest = FakeDigest(.success("Strong week."))
        let comment = await provider(digest).workoutComment(workout, language: "en")
        #expect(comment == CoachComment(text: "Strong week.", onDevice: false))
        #expect(digest.calls == 1)
    }

    @Test func withoutConsentNothingIsSentAndOnlyTheDeviceModelMayWrite() async {
        let digest = FakeDigest(.success("never"))
        #expect(await provider(digest, consent: false).workoutComment(workout, language: "en") == nil)
        let local = await provider(digest, consent: false, onDevice: "Nice work today.").workoutComment(workout, language: "en")
        #expect(local == CoachComment(text: "Nice work today.", onDevice: true))
        #expect(digest.calls == 0)
        #expect(await provider(digest, consent: false).weeklyComment(week, language: "en") == nil)
        #expect(digest.calls == 0)
    }

    @Test func aFreeUserFallsBackToTheDeviceForWorkoutsButNotForTheWeek() async {
        let digest = FakeDigest(.failure(.server(code: "pro_required", message: "")))
        let sut = provider(digest, onDevice: "Nice work today.")
        #expect(await sut.workoutComment(workout, language: "en") == CoachComment(text: "Nice work today.", onDevice: true))
        #expect(await sut.weeklyComment(week, language: "en") == nil)
    }

    @Test func theSettingsSwitchTurnsEverythingOff() async {
        let digest = FakeDigest(.success("x"))
        let off = provider(digest, enabled: false, onDevice: "y")
        #expect(await off.workoutComment(workout, language: "en") == nil)
        #expect(await off.weeklyComment(week, language: "en") == nil)
        #expect(await !off.mightCommentOnWorkout(language: "en"))
        #expect(await !off.mightCommentOnWeek())
        #expect(digest.calls == 0)
    }

    @Test func aFailureHidesTheSectionWhenTheDeviceCannotHelp() async {
        let digest = FakeDigest(.failure(.offline))
        #expect(await provider(digest).workoutComment(workout, language: "en") == nil)
        #expect(await provider(digest).weeklyComment(week, language: "tr") == nil)
    }

    @Test func theSwitchIsOnUntilTheUserTurnsItOff() {
        let defaults = UserDefaults(suiteName: "coach-comment-\(UUID().uuidString)")!
        #expect(CoachCommentProvider.storedSwitch(defaults))
        defaults.set(false, forKey: CoachPreferences.proactiveKey)
        #expect(!CoachCommentProvider.storedSwitch(defaults))
    }

    @Test func theWeeklyDigestUsesNamesNotIds() {
        let calendar = Calendar(identifier: .gregorian)
        let period = WeekPeriod.containing(Date(timeIntervalSince1970: 1_800_000_000), calendar: calendar)
        let summary = WeeklySummary(
            period: period, workouts: 3, goal: 4, totalSets: 40, previousSets: 30, volumeChange: 33.3,
            records: [RecordHighlight(exerciseId: "bench", kind: .e1rm, value: 100, date: period.start), RecordHighlight(exerciseId: "unknown", kind: .weight, value: 1, date: period.start)],
            overallScore: 54.4, overallChange: 2.64, exerciseChanges: [], topGroup: .chest, neglectedGroups: [.legs]
        )
        let digest = CoachDigestBuilder.weekly(summary, names: ["bench": "Bench Press"])
        #expect(digest.records == [DigestRecord(exercise: "Bench Press", kind: "e1rm")])
        #expect(digest.volumeChangePct == 33 && digest.overallScore == 54 && digest.overallChange == 2.6)
        #expect(digest.topGroup == "chest" && digest.neglectedGroups == ["legs"])
    }
}

import DataKit
import Foundation
import StrengthKit
import SwiftData
import Testing

@testable import ATROX

@MainActor
@Suite struct ExerciseScoreModelTests {
    private let bench = "barbell-bench-press-medium-grip"
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func makeModel(
        unit: ATROX.WeightUnit = .kilograms, language: String = "en", seedHistory: Bool = true
    ) async throws -> ExerciseScoreModel {
        let container = try DataStore.inMemory()
        let user = DataFixtures.userId
        try DataFixtures.seed(container, userId: user, now: now)
        if seedHistory {
            let workouts = SwiftDataWorkoutRepository(modelContainer: container)
            for draft in TrainingFixtures.twelveWeekHistory(now: now) { try await workouts.start(draft, userId: user) }
        }
        let scoring = ScoringModel(model: try EmbeddedModelBundle.model(), version: "1.0.0")
        let service = ScoreService(
            modelContainer: container, scoringModel: { scoring }, clock: { [now] in now }, calendar: Calendar(identifier: .gregorian)
        )
        return ExerciseScoreModel(
            exerciseID: bench, userId: user, service: service, population: .gym, unit: unit,
            locale: Locale(identifier: language == "tr" ? "tr_TR" : "en_US"), languageCode: language, name: { "Bench Press" }
        )
    }

    @Test func turkishSuffixFollowsTheLastSpokenNumber() {
        let expected: [Int: String] = [
            1: "'inden", 3: "'ünden", 4: "'ünden", 5: "'inden", 6: "'sından", 9: "'undan", 20: "'sinden", 40: "'ından",
            73: "'ünden", 76: "'sından", 99: "'undan", 100: "'ünden",
        ]
        for (number, suffix) in expected { #expect(ScoreSentence.turkishPossessiveAblative(number) == suffix, "\(number)") }
    }

    @Test func loadsTheScoreSentenceAndBasis() async throws {
        let model = try await makeModel()
        await model.load()
        let percentile = try #require(model.percentile)
        #expect((1...99).contains(percentile))
        #expect(model.sentenceSuffix.isEmpty)
        #expect(model.name == "Bench Press")
        #expect(model.basisText?.contains("e1RM") == true)
        #expect(model.levelName?.isEmpty == false)
        #expect(!model.densityPoints.isEmpty)
        #expect(model.userX != nil && model.medianX != nil)
    }

    @Test func turkishGetsTheNumberSuffix() async throws {
        let model = try await makeModel(language: "tr")
        await model.load()
        let percentile = try #require(model.percentile)
        #expect(model.sentenceSuffix == ScoreSentence.turkishPossessiveAblative(percentile))
    }

    @Test func switchingTheReferenceGroupRecomputes() async throws {
        let model = try await makeModel()
        await model.load()
        let gym = try #require(model.score)
        await model.select(.competitor)
        #expect(model.population == .competitor)
        #expect(model.insight?.population == .competitor)
        #expect(try #require(model.score) < gym)
        await model.select(.general)
        #expect(model.insight?.population == .general)
        #expect(model.sentenceKey == "general")
    }

    @Test func nextLevelTargetListsRoundedUpLoads() async throws {
        let model = try await makeModel()
        await model.load()
        let target = try #require(model.target)
        #expect(target.loads.count == ScoreService.targetReps.count)
        #expect(target.minScore > Int(try #require(model.score)))
        // Rounded up to a 2.5 kg step: every text shows a multiple of 2.5.
        for (text, load) in zip(target.loads, try #require(model.insight).targetLoads) {
            let shown = Double(text.split(separator: "×").last?.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: " kg", with: "").replacingOccurrences(of: ",", with: ".") ?? "") ?? 0
            #expect(shown >= load.weightKg - 1e-6 && shown.truncatingRemainder(dividingBy: 2.5) == 0, "\(text) vs \(load.weightKg)")
        }
    }

    @Test func densityStaysAnAreaInThePoundsUnit() async throws {
        let kg = try await makeModel()
        let lb = try await makeModel(unit: .pounds)
        await kg.load()
        await lb.load()
        func area(_ points: [ExerciseScoreModel.DensityPoint]) -> Double {
            zip(points, points.dropFirst()).reduce(0) { $0 + ($1.0.y + $1.1.y) / 2 * ($1.1.x - $1.0.x) }
        }
        #expect(abs(area(kg.densityPoints) - area(lb.densityPoints)) < 1e-6)
        #expect(try #require(lb.userX) > #require(kg.userX))
    }

    @Test func withoutHistoryTheScreenExplainsWhy() async throws {
        let model = try await makeModel(seedHistory: false)
        await model.load()
        #expect(model.insight?.notScorable == .noData)
        #expect(model.score == nil && model.target == nil)
    }
}

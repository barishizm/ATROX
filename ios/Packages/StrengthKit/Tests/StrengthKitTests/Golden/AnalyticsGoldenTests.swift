import Foundation
@testable import StrengthKit
import Testing

/// P062: aggregation, progress, imbalance and end-to-end against `ml/golden`.
@Suite struct AnalyticsGoldenTests {
    private let model = Golden.model

    struct AggregateCase: Decodable {
        struct Item: Decodable {
            let exerciseId: String, z: Double, confidence: ScoreConfidence, isMachine: Bool, anchor: AnchorLift?, stale: Bool
        }
        struct Input: Decodable { let scores: [Item] }
        struct Expected: Decodable { let muscles: [String: Golden.Group], overall: Golden.Group? }
        let input: Input
        let expected: Expected
    }

    static func check(_ actual: GroupScore?, _ expected: Golden.Group?, _ label: String) {
        guard let expected else {
            #expect(actual == nil, "\(label): expected none")
            return
        }
        guard let actual else {
            Issue.record("\(label): missing")
            return
        }
        #expect(Golden.close(actual.score, expected.score), "\(label) score \(actual.score) vs \(expected.score)")
        #expect(Golden.close(actual.z, expected.z), "\(label) z")
        #expect(actual.count == expected.n, "\(label) n")
        #expect(actual.confidence == expected.confidence, "\(label) confidence")
        #expect(actual.provisional == expected.provisional, "\(label) provisional")
        #expect(actual.level == expected.level, "\(label) level")
        #expect(actual.patterns == expected.patterns, "\(label) patterns")
    }

    static func checkGroups(_ muscles: [String: GroupScore], _ expected: [String: Golden.Group], _ label: String) {
        #expect(Set(muscles.keys) == Set(expected.keys), "\(label) muscle keys")
        for (key, group) in expected { check(muscles[key], group, "\(label) \(key)") }
    }

    @Test func aggregate() throws {
        for (idx, c) in try Golden.load("aggregate", as: AggregateCase.self).enumerated() {
            let scores = c.input.scores.map {
                ExerciseScore(
                    exerciseId: $0.exerciseId, score: 0, z: $0.z, bandLow: 0, bandHigh: 0, confidence: $0.confidence, level: "",
                    population: .gym, isMachine: $0.isMachine, anchor: $0.anchor, stale: $0.stale
                )
            }
            Self.checkGroups(try model.muscleGroupScores(scores), c.expected.muscles, "case \(idx)")
            Self.check(try model.overallScore(scores), c.expected.overall, "case \(idx) overall")
        }
    }

    struct ProgressCase: Decodable {
        struct Input: Decodable { let sessions: [[Double]], percentile: Double, trainingYears: Double? }
        struct Fit: Decodable { let slope: Double, intercept: Double, slopeLow: Double, slopeHigh: Double, n: Int }
        struct Trend: Decodable {
            let status: String, nSessions: Int, spanDays: Double, fit: Fit?, monthlyPct: Double?, sigma: Double?, tLast: Double?
        }
        struct Score: Decodable {
            let status: String, score: Double?, scoreLow: Double?, scoreHigh: Double?, ratio: Double?, expectedMonthlyPct: Double?
        }
        struct Plateau: Decodable { let status: String, nWindow: Int, nReference: Int, cusumMax: Double?, sigma: Double? }
        struct Point: Decodable { let weeks: Double, e1rm: Double, low: Double, high: Double }
        struct Forecast: Decodable { let status: String, points: [Point], slopeUsed: Double? }
        struct Expected: Decodable { let trend: Trend, score: Score, plateau: Plateau, forecast: Forecast }
        let input: Input
        let expected: Expected
    }

    @Test func progress() throws {
        let analyzer = ProgressAnalyzer(params: model.params.progress)
        for (idx, c) in try Golden.load("progress", as: ProgressCase.self).enumerated() {
            let sessions = c.input.sessions.map { ProgressAnalyzer.Session(day: $0[0], e1rmKg: $0[1]) }
            let rep = try analyzer.analyze(sessions, percentile: c.input.percentile, trainingYears: c.input.trainingYears)
            let exp = c.expected, label = "case \(idx)"
            #expect(rep.trend.status.rawValue == exp.trend.status, "\(label) trend status")
            #expect(rep.trend.sessionCount == exp.trend.nSessions, "\(label) n")
            #expect(Golden.close(rep.trend.spanDays, exp.trend.spanDays), "\(label) span")
            #expect(Golden.close(rep.trend.fit?.slope, exp.trend.fit?.slope, tol: 1e-9), "\(label) slope")
            #expect(Golden.close(rep.trend.fit?.slopeLow, exp.trend.fit?.slopeLow, tol: 1e-9), "\(label) slopeLow")
            #expect(Golden.close(rep.trend.fit?.slopeHigh, exp.trend.fit?.slopeHigh, tol: 1e-9), "\(label) slopeHigh")
            #expect(Golden.close(rep.trend.fit?.intercept, exp.trend.fit?.intercept), "\(label) intercept")
            #expect(Golden.close(rep.trend.monthlyPct, exp.trend.monthlyPct), "\(label) monthly")
            #expect(Golden.close(rep.trend.sigma, exp.trend.sigma), "\(label) sigma")
            #expect(rep.score.status.rawValue == exp.score.status, "\(label) score status")
            #expect(Golden.close(rep.score.score, exp.score.score), "\(label) score")
            #expect(Golden.close(rep.score.scoreLow, exp.score.scoreLow), "\(label) scoreLow")
            #expect(Golden.close(rep.score.scoreHigh, exp.score.scoreHigh), "\(label) scoreHigh")
            #expect(Golden.close(rep.score.ratio, exp.score.ratio), "\(label) ratio")
            #expect(rep.plateau.status.rawValue == exp.plateau.status, "\(label) plateau")
            #expect(rep.plateau.windowCount == exp.plateau.nWindow && rep.plateau.referenceCount == exp.plateau.nReference)
            #expect(Golden.close(rep.plateau.cusumMax, exp.plateau.cusumMax), "\(label) cusum")
            #expect(rep.forecast.status.rawValue == exp.forecast.status, "\(label) forecast status")
            #expect(rep.forecast.points.count == exp.forecast.points.count, "\(label) points")
            for (got, want) in zip(rep.forecast.points, exp.forecast.points) {
                #expect(Golden.close(got.e1rmKg, want.e1rm) && Golden.close(got.low, want.low) && Golden.close(got.high, want.high))
            }
        }
    }

    struct ImbalanceCase: Decodable {
        struct Score: Decodable {
            let exerciseId: String, z: Double, confidence: ScoreConfidence, pattern: String, isMachine: Bool, corrKey: String?
            let muscles: [String]
        }
        struct Uni: Decodable {
            let exerciseId: String, leftKg: Double, rightKg: Double, confidence: ScoreConfidence, isMachine: Bool, muscles: [String]
        }
        struct Input: Decodable { let scores: [Score], unilateral: [Uni] }
        struct Finding: Decodable {
            let kind: String, ruleId: String, severity: String, magnitude: Double, weakGroup: String, strongGroup: String?
            let weakExerciseIds: [String], strongExerciseIds: [String], muscles: [String], recommendationKey: String
            let metrics: [String: Double]
        }
        let input: Input
        let expected: [Finding]
    }

    @Test func imbalance() throws {
        let analyzer = try ImbalanceAnalyzer(params: model.params.imbalance, correlation: model.params.correlation)
        for (idx, c) in try Golden.load("imbalance", as: ImbalanceCase.self).enumerated() {
            let scores = c.input.scores.map {
                ImbalanceAnalyzer.ScoreInput(
                    exerciseId: $0.exerciseId, z: $0.z, confidence: $0.confidence, pattern: $0.pattern, isMachine: $0.isMachine,
                    corrKey: $0.corrKey, muscles: $0.muscles
                )
            }
            let uni = c.input.unilateral.map {
                ImbalanceAnalyzer.UnilateralInput(
                    exerciseId: $0.exerciseId, leftKg: $0.leftKg, rightKg: $0.rightKg, confidence: $0.confidence,
                    isMachine: $0.isMachine, muscles: $0.muscles
                )
            }
            let found = try analyzer.analyze(scores, unilateral: uni)
            #expect(found.count == c.expected.count, "case \(idx): count \(found.count) vs \(c.expected.count)")
            for (got, want) in zip(found, c.expected) {
                #expect(got.kind.rawValue == want.kind && got.ruleId == want.ruleId && got.severity.rawValue == want.severity)
                #expect(Golden.close(got.magnitude, want.magnitude), "case \(idx) magnitude")
                #expect(got.weakGroup == want.weakGroup && got.strongGroup == want.strongGroup)
                #expect(got.weakExerciseIds == want.weakExerciseIds && got.strongExerciseIds == want.strongExerciseIds)
                #expect(got.muscles == want.muscles && got.recommendationKey == want.recommendationKey)
                #expect(Set(got.metrics.keys) == Set(want.metrics.keys))
                for (key, value) in want.metrics { #expect(Golden.close(got.metrics[key], value), "case \(idx) \(key)") }
            }
        }
    }

    struct EndToEndCase: Decodable {
        struct Exercise: Decodable { let exerciseId: String, sets: [Golden.LoggedSet] }
        struct Input: Decodable { let user: Golden.User, asOfDay: Int, population: ReferencePopulation, exercises: [Exercise] }
        struct Expected: Decodable {
            let exercises: [String: Golden.Score?]
            let muscles: [String: Golden.Group]
            let overall: Golden.Group?
        }
        let input: Input
        let expected: Expected
    }

    /// Mirrors ml `golden.end_to_end_cases`: reps_only uses the best set's reps, others the current strength.
    static func scoreAll(_ model: StrengthModel, _ input: EndToEndCase.Input) throws -> [String: ExerciseScore?] {
        var out: [String: ExerciseScore?] = [:]
        let user = input.user.scoring
        for ex in input.exercises {
            let sets = ex.sets.map(\.scoring)
            let tax = try model.exercise(ex.exerciseId)
            if tax.scoringType == "reps_only" {
                let reps = Double(sets.map(\.reps).max() ?? 0)
                let none = CurrentStrength(e1rmKg: nil, confidence: .low, stale: false, sessionsInWindow: 0)
                out[ex.exerciseId] = try model.exerciseScore(tax, strength: none, user: user, population: input.population, reps: reps)
            } else {
                let strength = try model.currentStrength(tax, sets: sets, user: user, asOfDay: input.asOfDay)
                out[ex.exerciseId] = try model.exerciseScore(tax, strength: strength, user: user, population: input.population)
            }
        }
        return out
    }

    @Test func endToEnd() throws {
        for (idx, c) in try Golden.load("end_to_end", as: EndToEndCase.self).enumerated() {
            let scores = try Self.scoreAll(model, c.input)
            for (id, want) in c.expected.exercises { Golden.check(scores[id] ?? nil, want, "case \(idx) \(id)") }
            let order = c.input.exercises.compactMap { scores[$0.exerciseId] ?? nil }
            Self.checkGroups(try model.muscleGroupScores(order), c.expected.muscles, "case \(idx)")
            Self.check(try model.overallScore(order), c.expected.overall, "case \(idx) overall")
        }
    }

    @Test func allScoresOfA150ExerciseUserUnder50ms() throws {
        let ids = model.exercises.keys.sorted().prefix(150)
        #expect(ids.count == 150)
        let user = ScoringUser(sex: .female, age: 34, bodyweightKg: 64)
        let sets = (0..<6).map { ScoringSet(day: 300 - 7 * $0, weightKg: 20 + Double($0), reps: 8, rir: 2) }
        let clock = ContinuousClock()
        var scores: [ExerciseScore] = []
        let elapsed = try clock.measure {
            for id in ids {
                let tax = try model.exercise(id)
                let strength = try model.currentStrength(tax, sets: sets, user: user, asOfDay: 300)
                if let score = try model.exerciseScore(tax, strength: strength, user: user, reps: 20) { scores.append(score) }
            }
            _ = try model.muscleGroupScores(scores)
            _ = try model.overallScore(scores)
        }
        #expect(scores.count >= 100)  // reps_only moves without norms are not scored
        #expect(elapsed < .milliseconds(50), "took \(elapsed)")
    }
}

@Suite struct ModelBundleTests {
    @Test func scoreEngineScoresOnboardingLifts() throws {
        let engine = ModelScoreEngine()
        let athlete = AthleteProfile(sex: .male, bodyweightKg: 80, ageYears: 30)
        let weak = try #require(engine.estimate(LiftSet(lift: .benchPress, implement: .barbell, weightKg: 50, reps: 5), for: athlete))
        let strong = try #require(engine.estimate(LiftSet(lift: .benchPress, implement: .barbell, weightKg: 120, reps: 5), for: athlete))
        #expect(weak.score < strong.score && !strong.isPlaceholder)
        for lift in BasicLift.allCases {
            for implement in LiftImplement.allCases {
                let set = LiftSet(lift: lift, implement: implement, weightKg: 30, reps: 5)
                #expect(engine.estimate(set, for: athlete) != nil, "\(lift) \(implement)")
            }
        }
        #expect(engine.estimate(LiftSet(lift: .squat, implement: .barbell, weightKg: 0, reps: 5), for: athlete) == nil)
    }

    #if canImport(CryptoKit)
    private static func copyEmbedded() throws -> URL {
        let source = try #require(EmbeddedModelBundle.directory)
        let dest = FileManager.default.temporaryDirectory.appendingPathComponent("bundle-\(UUID().uuidString)")
        try FileManager.default.copyItem(at: source, to: dest)
        return dest
    }

    @Test func embeddedBundleVerifies() throws {
        let bundle = try ModelBundle.embedded(appVersion: "1.0.0")
        #expect(bundle.manifest.version == "1.0.0" && bundle.manifest.anchor.kind == "tables")
        #expect(throws: StrengthModelError.self) { try ModelBundle.embedded(appVersion: "0.9.0") }
    }

    @Test func tamperedBundleIsRejectedAndEmbeddedIsUsed() throws {
        let dir = try Self.copyEmbedded()
        defer { try? FileManager.default.removeItem(at: dir) }
        let params = dir.appendingPathComponent("params.json")
        let text = try String(contentsOf: params, encoding: .utf8).replacingOccurrences(of: "\"windowDays\":42", with: "\"windowDays\":43")
        try Data(text.utf8).write(to: params)
        #expect(throws: StrengthModelError.bundle("SHA-256 mismatch for params.json")) {
            try ModelBundle.load(from: dir, appVersion: "1.0.0")
        }
        let fallback = try ModelBundle.loadPreferred(candidate: dir, appVersion: "1.0.0")
        #expect(fallback.directory.standardizedFileURL == EmbeddedModelBundle.directory?.standardizedFileURL)
        #expect(fallback.model.params.currentStrength.windowDays == 42)
    }

    @Test func forgedManifestFailsSignature() throws {
        let dir = try Self.copyEmbedded()
        defer { try? FileManager.default.removeItem(at: dir) }
        let manifest = dir.appendingPathComponent("manifest.json")
        let text = try String(contentsOf: manifest, encoding: .utf8).replacingOccurrences(of: "\"minAppVersion\":\"1.0.0\"", with: "\"minAppVersion\":\"0.0.1\"")
        try Data(text.utf8).write(to: manifest)
        #expect(throws: StrengthModelError.bundle("manifest signature is invalid")) {
            try ModelBundle.load(from: dir, appVersion: "1.0.0")
        }
    }
    #endif
}

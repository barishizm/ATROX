// swiftlint:disable identifier_name nesting line_length optional_data_string_conversion
import Foundation
@testable import StrengthKit
import Testing

/// Golden vectors written by ml `make export` (`ml/golden/*.json`); Swift must match Python within 1e-4.
enum Golden {
    static let tolerance = 1e-4

    struct File<Case: Decodable>: Decodable {
        let layer: String
        let tolerance: Double
        let cases: [Case]
    }

    struct User: Decodable {
        let sex: ModelSex?
        let age: Double
        let bodyweightKg: Double

        var scoring: ScoringUser { ScoringUser(sex: sex, age: age, bodyweightKg: bodyweightKg) }
    }

    struct LoggedSet: Decodable {
        let day: Int
        let weightKg: Double
        let reps: Int
        let rir: Double?
        let isWarmup: Bool
        let confirmed: Bool

        var scoring: ScoringSet {
            ScoringSet(day: day, weightKg: weightKg, reps: reps, rir: rir, isWarmup: isWarmup, confirmed: confirmed)
        }
    }

    struct Score: Decodable {
        let score: Double
        let z: Double
        let bandLow: Double
        let bandHigh: Double
        let confidence: ScoreConfidence
        let level: String
        let isMachine: Bool
        let anchor: AnchorLift?
        let stale: Bool
    }

    struct Group: Decodable {
        let score: Double
        let z: Double
        let n: Int
        let confidence: ScoreConfidence
        let provisional: Bool
        let level: String
        let patterns: [String]
    }

    /// `ml/golden`, found by walking up from this file (works on macOS and the Linux CI container).
    static var directory: URL {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<12 {
            url.deleteLastPathComponent()
            let candidate = url.appendingPathComponent("ml/golden")
            if FileManager.default.fileExists(atPath: candidate.appendingPathComponent("e1rm.json").path) { return candidate }
        }
        return url.appendingPathComponent("ml/golden")
    }

    static func load<Case: Decodable>(_ name: String, as _: Case.Type = Case.self) throws -> [Case] {
        let data = try Data(contentsOf: directory.appendingPathComponent("\(name).json"))
        let file = try JSONDecoder().decode(File<Case>.self, from: data)
        #expect(file.layer == name)
        #expect(!file.cases.isEmpty)
        return file.cases
    }

    static let model: StrengthModel = {
        do { return try EmbeddedModelBundle.model() } catch { fatalError("embedded bundle: \(error)") }
    }()

    static func close(_ actual: Double, _ expected: Double, tol: Double = tolerance) -> Bool {
        abs(actual - expected) <= tol
    }

    static func close(_ actual: Double?, _ expected: Double?, tol: Double = tolerance) -> Bool {
        switch (actual, expected) {
        case (nil, nil): true
        case let (lhs?, rhs?): close(lhs, rhs, tol: tol)
        default: false
        }
    }

    static func check(_ actual: ExerciseScore?, _ expected: Score?, _ label: String, sourceLocation: SourceLocation = #_sourceLocation) {
        guard let expected else {
            #expect(actual == nil, "\(label): expected no score", sourceLocation: sourceLocation)
            return
        }
        guard let actual else {
            Issue.record("\(label): missing score", sourceLocation: sourceLocation)
            return
        }
        #expect(close(actual.score, expected.score), "\(label) score \(actual.score) vs \(expected.score)", sourceLocation: sourceLocation)
        #expect(close(actual.z, expected.z), "\(label) z \(actual.z) vs \(expected.z)", sourceLocation: sourceLocation)
        #expect(close(actual.bandLow, expected.bandLow), "\(label) bandLow", sourceLocation: sourceLocation)
        #expect(close(actual.bandHigh, expected.bandHigh), "\(label) bandHigh", sourceLocation: sourceLocation)
        #expect(actual.confidence == expected.confidence, "\(label) confidence", sourceLocation: sourceLocation)
        #expect(actual.level == expected.level, "\(label) level", sourceLocation: sourceLocation)
        #expect(actual.isMachine == expected.isMachine, "\(label) isMachine", sourceLocation: sourceLocation)
        #expect(actual.anchor == expected.anchor, "\(label) anchor", sourceLocation: sourceLocation)
        #expect(actual.stale == expected.stale, "\(label) stale", sourceLocation: sourceLocation)
    }
}

import Foundation

/// Errors of the scoring model. Invalid input never crashes; it surfaces as one of these.
public enum StrengthModelError: Error, Equatable, Sendable {
    case invalidInput(String)
    case missingParameter(String)
    case unsupportedSchema(found: Int, supported: Int)
    case decoding(String)
    case bundle(String)
}

public enum ModelSex: String, Codable, Sendable, CaseIterable {
    case male = "M"
    case female = "F"
}

public enum ScoreConfidence: String, Codable, Sendable, Comparable, CaseIterable {
    case low, medium, high

    private var rank: Int {
        switch self {
        case .low: 0
        case .medium: 1
        case .high: 2
        }
    }

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rank < rhs.rank }
}

/// Reference population the percentile is computed against (docs/03-ML-MODEL.md §5).
public enum ReferencePopulation: String, Codable, Sendable, CaseIterable {
    case competitor, gym, general
}

/// The three anchor lifts of the competitor model.
public enum AnchorLift: String, Codable, Sendable, CaseIterable {
    case squat, bench, deadlift
}

// MARK: - params.json (schema 1, written by ml `make export`)

public struct ModelParams: Codable, Sendable {
    public static let supportedSchemaVersion = 1

    public let schemaVersion: Int
    public let e1rm: E1RMParams
    public let currentStrength: CurrentStrengthParams
    public let anchor: AnchorParams
    public let exerciseScore: ExerciseScoreParams
    public let calibration: CalibrationParams
    public let correlation: CorrelationParams
    public let aggregate: AggregateParams
    public let levels: [LevelThreshold]
    public let progress: ProgressParams
    public let imbalance: ImbalanceParams
    public let repNorms: [RepNormPoint]
    public let inputClip: InputClip

    /// Decodes and checks the schema version.
    public static func decode(_ data: Data) throws(StrengthModelError) -> ModelParams {
        try checkSchema(data, supported: supportedSchemaVersion)
        return try decodeJSON(data)
    }
}

public struct E1RMParams: Codable, Sendable {
    public struct Curve: Codable, Sendable {
        public let k: Double
        public let p: Double
    }

    public struct Confidence: Codable, Sendable {
        public let knotsReps: [Double]
        public let knotsConf: [Double]
        public let noRirFactor: Double
    }

    public let family: String
    public let rMax: Double
    public let defaultCategory: String
    public let patternCategory: [String: String]
    public let categories: [String: Curve]
    public let confidence: Confidence
}

public struct CurrentStrengthParams: Codable, Sendable {
    public struct Level: Codable, Sendable {
        public let minSessions: Int
        public let maxDaysSinceLast: Int
        public let minMeanSetConfidence: Double
    }

    public let windowDays: Int
    public let outlierJump: Double
    public let staleDecayPerWeek: Double
    public let minSetConfidence: Double
    public let confidenceLevels: [String: Level]
}

public struct AnchorParams: Codable, Sendable {
    public let cdfClip: [Double]
    public let scaleQuantiles: [Double]
}

public struct ExerciseScoreParams: Codable, Sendable {
    public let populations: [String]
    public let defaultPopulation: ReferencePopulation
    public let scoreClip: [Double]
    public let calibrationMinAge: Double
    public let unspecifiedSexMix: [String: Double]
    public let gradeConfidenceCap: [String: ScoreConfidence]
    public let machineConventions: [String]
    public let machineEquipment: [String]
}

public struct CalibrationParams: Codable, Sendable {
    public struct AgeBand: Codable, Sendable {
        public let key: String
        public let min: Double
        public let max: Double
    }

    public let ageBands: [AgeBand]
    /// population → sex → lift → age band → δ (log scale).
    public let delta: [String: [String: [String: [String: Double]]]]
    /// population → sex → κ.
    public let kappa: [String: [String: Double]]
    /// population → median half width of the uncertainty band (percentile points).
    public let uncertaintyHalfWidth: [String: Double]
}

public struct CorrelationParams: Codable, Sendable {
    public let variables: [String]
    public let matrix: [[Double]]
}

public struct AggregateParams: Codable, Sendable {
    public struct MuscleWeights: Codable, Sendable {
        public let primary: Double
        public let secondary: Double
    }

    public let muscleWeights: MuscleWeights
    public let confidenceWeights: [String: Double]
    public let staleWeight: Double
    public let machineWeight: Double
    public let unknownPairCorrelation: Double
    public let sameAnchorCorrelation: Double
    public let patternCorrelation: Double
    public let patterns: [String]
    public let upperPatterns: [String]
    public let lowerPatterns: [String]
    public let minPatternsForFullScore: Int
}

public struct LevelThreshold: Codable, Sendable {
    public let key: String
    public let min: Double
}

public struct RepNormPoint: Codable, Sendable {
    public let exerciseIds: [String]
    public let sex: ModelSex
    public let ageMin: Int
    public let ageMax: Int
    public let percentile: Double
    public let reps: Double
}

public struct InputClip: Codable, Sendable {
    public let age: [Double]
    public let bodyweightKg: [Double]
}

public struct ProgressParams: Codable, Sendable {
    public struct Trend: Codable, Sendable {
        public let windowWeeksMax: Double
        public let minSessions: Int
        public let minSpanWeeks: Double
        public let ciLevel: Double
        public let ciZ: Double
    }

    public struct ExpectedCurve: Codable, Sendable {
        public let noviceMonthlyGain: Double
        public let floorMonthlyGain: Double
        public let levelDecay: Double
        public let experienceHalfLifeYears: Double
    }

    public struct Score: Codable, Sendable {
        public let ratioAnchors: [Double]
        public let scoreAnchors: [Double]
    }

    public struct Plateau: Codable, Sendable {
        public let windowWeeks: Double
        public let referenceWeeks: Double
        public let referenceMinSessions: Int
        public let medianVarianceFactor: Double
        public let minSessionsPerWeek: Double
        public let k: Double
        public let h: Double
        public let clipZ: Double
        public let sigmaFloor: Double
        public let madToSigma: Double
    }

    public struct Forecast: Codable, Sendable {
        public let horizonsWeeks: [Double]
        public let maxHorizonWeeks: Double
        public let dampingDays: Double
        public let maxRatioToExpected: Double
        public let maxMonthlyLoss: Double
    }

    public let daysPerMonth: Double
    public let trend: Trend
    public let expectedCurve: ExpectedCurve
    public let score: Score
    public let plateau: Plateau
    public let forecast: Forecast
}

public struct ImbalanceParams: Codable, Sendable {
    public struct RatioRule: Codable, Sendable {
        public let id: String
        public let groupA: String
        public let patternsA: [String]
        public let groupB: String
        public let patternsB: [String]
        public let minExercisesPerGroup: Int
        public let severityZGap: [Double]
    }

    public let minVariables: Int
    public let severitySd: [Double]
    public let unknownPairCorrelation: Double
    public let confidenceWeights: [String: Double]
    public let allowedConfidence: [ScoreConfidence]
    public let excludeMachine: Bool
    public let ratioRules: [RatioRule]
    public let severityAsymmetry: [Double]
}

// MARK: - taxonomy.json

public struct ModelTaxonomy: Codable, Sendable {
    public static let supportedSchemaVersion = 1

    public let schemaVersion: Int
    public let exercises: [TaxonomyExercise]

    public static func decode(_ data: Data) throws(StrengthModelError) -> ModelTaxonomy {
        try checkSchema(data, supported: supportedSchemaVersion)
        return try decodeJSON(data)
    }
}

/// Scoring fields of one catalog exercise (only scorable exercises are exported).
public struct TaxonomyExercise: Codable, Sendable, Equatable {
    public let id: String
    public let movementPattern: String?
    /// weighted | bodyweight_loaded | reps_only | time | none
    public let scoringType: String
    public let loadConvention: String?
    public let anchor: AnchorLift?
    /// Anchor ratio in the unit the user logs (per hand / per side / total / bodyweight + added).
    public let ratio: Double?
    public let tau: Double?
    /// A | B | C
    public let ratioConfidence: String?
    public let bwFraction: Double?
    public let isAnchor: Bool
    public let isUnilateral: Bool
    public let primaryMuscles: [String]
    public let secondaryMuscles: [String]
    public let equipment: String?

    public init(
        id: String, movementPattern: String?, scoringType: String, loadConvention: String? = nil,
        anchor: AnchorLift? = nil, ratio: Double? = nil, tau: Double? = nil, ratioConfidence: String? = nil,
        bwFraction: Double? = nil, isAnchor: Bool = false, isUnilateral: Bool = false,
        primaryMuscles: [String] = [], secondaryMuscles: [String] = [], equipment: String? = nil
    ) {
        self.id = id
        self.movementPattern = movementPattern
        self.scoringType = scoringType
        self.loadConvention = loadConvention
        self.anchor = anchor
        self.ratio = ratio
        self.tau = tau
        self.ratioConfidence = ratioConfidence
        self.bwFraction = bwFraction
        self.isAnchor = isAnchor
        self.isUnilateral = isUnilateral
        self.primaryMuscles = primaryMuscles
        self.secondaryMuscles = secondaryMuscles
        self.equipment = equipment
    }

    public var scorable: Bool {
        if scoringType == "reps_only" { return true }
        return (scoringType == "weighted" || scoringType == "bodyweight_loaded") && anchor != nil
    }
}

/// Reads only `schemaVersion` first so a newer file fails as "unsupported", not as a decoding error.
func checkSchema(_ data: Data, supported: Int) throws(StrengthModelError) {
    struct Header: Decodable { let schemaVersion: Int }
    let header: Header = try decodeJSON(data)
    guard header.schemaVersion == supported else { throw .unsupportedSchema(found: header.schemaVersion, supported: supported) }
}

func decodeJSON<T: Decodable>(_ data: Data) throws(StrengthModelError) -> T {
    do {
        return try JSONDecoder().decode(T.self, from: data)
    } catch {
        throw .decoding(String(describing: error))
    }
}

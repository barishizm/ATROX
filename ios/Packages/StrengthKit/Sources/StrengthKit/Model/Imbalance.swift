// swiftlint:disable identifier_name nesting
import Foundation

/// Imbalance analysis (docs/03-ML-MODEL.md §10), a 1:1 port of `gymml.imbalance`. Findings carry no text; the app
/// picks a localized template by `recommendationKey`.
public struct ImbalanceAnalyzer: Sendable {
    public enum Severity: String, Sendable, CaseIterable, Comparable {
        case mild, moderate, severe

        var rank: Int { Self.allCases.firstIndex(of: self) ?? 0 }
        public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rank < rhs.rank }
    }

    public enum Kind: String, Sendable {
        case conditionalResidual = "conditional_residual", ratioRule = "ratio_rule", leftRight = "left_right"

        var order: Int {
            switch self {
            case .conditionalResidual: 0
            case .ratioRule: 1
            case .leftRight: 2
            }
        }
    }

    /// One exercise score in z space. `corrKey` names a correlation variable (only for the anchor lift itself).
    public struct ScoreInput: Sendable, Equatable {
        public var exerciseId: String
        public var z: Double
        public var confidence: ScoreConfidence
        public var pattern: String
        public var isMachine: Bool
        public var corrKey: String?
        public var muscles: [String]

        public init(
            exerciseId: String, z: Double, confidence: ScoreConfidence, pattern: String, isMachine: Bool = false,
            corrKey: String? = nil, muscles: [String] = []
        ) {
            self.exerciseId = exerciseId
            self.z = z
            self.confidence = confidence
            self.pattern = pattern
            self.isMachine = isMachine
            self.corrKey = corrKey
            self.muscles = muscles
        }
    }

    /// Left and right e1RM of one unilateral exercise.
    public struct UnilateralInput: Sendable, Equatable {
        public var exerciseId: String
        public var leftKg: Double
        public var rightKg: Double
        public var confidence: ScoreConfidence
        public var isMachine: Bool
        public var muscles: [String]

        public init(
            exerciseId: String, leftKg: Double, rightKg: Double, confidence: ScoreConfidence, isMachine: Bool = false,
            muscles: [String] = []
        ) {
            self.exerciseId = exerciseId
            self.leftKg = leftKg
            self.rightKg = rightKg
            self.confidence = confidence
            self.isMachine = isMachine
            self.muscles = muscles
        }
    }

    public struct Finding: Sendable, Equatable {
        public var kind: Kind
        public var ruleId: String
        public var severity: Severity
        public var magnitude: Double
        public var weakGroup: String
        public var strongGroup: String?
        public var weakExerciseIds: [String]
        public var strongExerciseIds: [String]
        public var muscles: [String]
        public var recommendationKey: String
        public var metrics: [String: Double]
    }

    public let params: ImbalanceParams
    public let variables: [String]
    public let correlation: [[Double]]

    public init(params: ImbalanceParams, correlation: CorrelationParams) throws(StrengthModelError) {
        guard params.severitySd.count == 3, params.severityAsymmetry.count == 3, params.minVariables >= 2,
              correlation.matrix.count == correlation.variables.count,
              correlation.matrix.allSatisfy({ $0.count == correlation.variables.count }) else {
            throw .invalidInput("imbalance parameters malformed")
        }
        self.params = params
        self.variables = correlation.variables
        self.correlation = correlation.matrix
    }

    private func severity(_ value: Double, _ ladder: [Double]) -> Severity? {
        var level: Severity?
        for (sev, threshold) in zip(Severity.allCases, ladder) where value >= threshold { level = sev }
        return level
    }

    private func passesGate(_ confidence: ScoreConfidence, isMachine: Bool) -> Bool {
        params.allowedConfidence.contains(confidence) && !(params.excludeMachine && isMachine)
    }

    private static func sortedUnique(_ items: [String]) -> [String] { Array(Set(items)).sorted() }

    // MARK: Conditional residual

    /// E[z_t | z_g] and the conditional SD for a standard multivariate normal with this correlation.
    func conditionalMoments(target: Int, given: [Int], zGiven: [Double]) -> (mean: Double, sd: Double)? {
        let sgg = given.map { gi in given.map { correlation[gi][$0] } }
        let stg = given.map { correlation[target][$0] }
        guard let beta = Self.solve(sgg, stg) else { return nil }
        let mean = zip(beta, zGiven).reduce(0) { $0 + $1.0 * $1.1 }
        let variance = 1 - zip(stg, beta).reduce(0) { $0 + $1.0 * $1.1 }
        return (mean, max(variance, 0).squareRoot())
    }

    /// Gaussian elimination with partial pivoting (tiny symmetric positive-definite systems).
    static func solve(_ matrix: [[Double]], _ rhs: [Double]) -> [Double]? {
        var a = matrix, b = rhs
        let n = b.count
        for col in 0..<n {
            guard let pivot = (col..<n).max(by: { abs(a[$0][col]) < abs(a[$1][col]) }), abs(a[pivot][col]) > 1e-300 else {
                return nil
            }
            a.swapAt(col, pivot)
            b.swapAt(col, pivot)
            for row in (col + 1)..<max(n, col + 1) {
                let factor = a[row][col] / a[col][col]
                for k in col..<n { a[row][k] -= factor * a[col][k] }
                b[row] -= factor * b[col]
            }
        }
        var x = [Double](repeating: 0, count: n)
        for row in stride(from: n - 1, through: 0, by: -1) {
            var sum = b[row]
            for k in (row + 1)..<max(n, row + 1) { sum -= a[row][k] * x[k] }
            x[row] = sum / a[row][row]
        }
        return x
    }

    private struct Candidate {
        let absR: Double
        let target: Int
        let mean: Double
        let sd: Double
    }

    func residualFindings(_ scores: [ScoreInput]) throws(StrengthModelError) -> [Finding] {
        var byKey: [String: ScoreInput] = [:]
        for score in scores {
            guard let key = score.corrKey, passesGate(score.confidence, isMachine: score.isMachine), variables.contains(key) else {
                continue
            }
            if byKey[key] != nil { throw .invalidInput("duplicate score for correlation variable \(key)") }
            byKey[key] = score
        }
        var active = variables.indices.filter { byKey[variables[$0]] != nil }
        var findings: [Finding] = []
        while active.count >= params.minVariables {
            var best: Candidate?
            for target in active {
                let given = active.filter { $0 != target }
                let zGiven = given.compactMap { byKey[variables[$0]]?.z }
                guard let moments = conditionalMoments(target: target, given: given, zGiven: zGiven), moments.sd > 0,
                      let observed = byKey[variables[target]]?.z else { continue }
                let resid = (observed - moments.mean) / moments.sd
                if best == nil || abs(resid) > best?.absR ?? 0 { best = Candidate(absR: abs(resid), target: target, mean: moments.mean, sd: moments.sd) }
            }
            guard let best, let sev = severity(best.absR, params.severitySd),
                  let target = byKey[variables[best.target]] else { break }
            let name = variables[best.target]
            let others = active.filter { $0 != best.target }.compactMap { byKey[variables[$0]] }
            let below = target.z < best.mean
            let otherIds = others.map(\.exerciseId).sorted()
            findings.append(Finding(
                kind: .conditionalResidual, ruleId: name, severity: sev, magnitude: best.absR,
                weakGroup: below ? name : "others", strongGroup: below ? "others" : name,
                weakExerciseIds: below ? [target.exerciseId] : otherIds, strongExerciseIds: below ? otherIds : [target.exerciseId],
                muscles: Self.sortedUnique((below ? [target] : others).flatMap(\.muscles)),
                recommendationKey: "\(Kind.conditionalResidual.rawValue).\(name).\(below ? "below_expected" : "above_expected")",
                metrics: [
                    "observed_z": target.z, "expected_z": best.mean, "residual_sd": best.sd,
                    "standardized_residual": (target.z - best.mean) / best.sd,
                ]
            ))
            active.removeAll { $0 == best.target }
        }
        return findings
    }

    // MARK: Ratio rules

    func combineZ(_ items: [ScoreInput]) -> Double {
        let weights = items.map { params.confidenceWeights[$0.confidence.rawValue] ?? 0 }
        var num = 0.0, den = 0.0
        for (weight, item) in zip(weights, items) {
            num += weight * item.z
            den += weight * weight
        }
        for i in items.indices {
            for j in (i + 1)..<max(items.count, i + 1) { den += 2 * weights[i] * weights[j] * pairCorrelation(items[i], items[j]) }
        }
        return num / den.squareRoot()
    }

    private func pairCorrelation(_ lhs: ScoreInput, _ rhs: ScoreInput) -> Double {
        if let lk = lhs.corrKey, let rk = rhs.corrKey, lk != rk, let li = variables.firstIndex(of: lk),
           let ri = variables.firstIndex(of: rk) {
            return correlation[li][ri]
        }
        return params.unknownPairCorrelation
    }

    func ratioFindings(_ scores: [ScoreInput]) -> [Finding] {
        let eligible = scores.filter { passesGate($0.confidence, isMachine: $0.isMachine) }.sorted { $0.exerciseId < $1.exerciseId }
        var findings: [Finding] = []
        for rule in params.ratioRules {
            let groupA = eligible.filter { rule.patternsA.contains($0.pattern) }
            let groupB = eligible.filter { rule.patternsB.contains($0.pattern) }
            guard min(groupA.count, groupB.count) >= rule.minExercisesPerGroup else { continue }
            let za = combineZ(groupA), zb = combineZ(groupB)
            let gap = abs(za - zb)
            guard let sev = severity(gap, rule.severityZGap) else { continue }
            let aWeak = za < zb
            let (weakName, strongName) = aWeak ? (rule.groupA, rule.groupB) : (rule.groupB, rule.groupA)
            let (weak, strong) = aWeak ? (groupA, groupB) : (groupB, groupA)
            findings.append(Finding(
                kind: .ratioRule, ruleId: rule.id, severity: sev, magnitude: gap, weakGroup: weakName, strongGroup: strongName,
                weakExerciseIds: weak.map(\.exerciseId).sorted(), strongExerciseIds: strong.map(\.exerciseId).sorted(),
                muscles: Self.sortedUnique(weak.flatMap(\.muscles)),
                recommendationKey: "\(Kind.ratioRule.rawValue).\(rule.id).\(weakName)_behind",
                metrics: ["weak_z": min(za, zb), "strong_z": max(za, zb), "z_gap": gap]
            ))
        }
        return findings
    }

    // MARK: Left / right

    func leftRightFindings(_ pairs: [UnilateralInput]) throws(StrengthModelError) -> [Finding] {
        var findings: [Finding] = []
        for pair in pairs.sorted(by: { $0.exerciseId < $1.exerciseId }) {
            guard pair.leftKg > 0, pair.rightKg > 0 else { throw .invalidInput("e1RM must be positive for \(pair.exerciseId)") }
            guard passesGate(pair.confidence, isMachine: pair.isMachine), pair.leftKg != pair.rightKg else { continue }
            let strong = max(pair.leftKg, pair.rightKg), weak = min(pair.leftKg, pair.rightKg)
            let asym = (strong - weak) / strong
            guard let sev = severity(asym, params.severityAsymmetry) else { continue }
            let weakSide = pair.leftKg < pair.rightKg ? "left" : "right"
            findings.append(Finding(
                kind: .leftRight, ruleId: pair.exerciseId, severity: sev, magnitude: asym, weakGroup: weakSide,
                strongGroup: weakSide == "left" ? "right" : "left", weakExerciseIds: [pair.exerciseId],
                strongExerciseIds: [pair.exerciseId], muscles: Self.sortedUnique(pair.muscles),
                recommendationKey: "\(Kind.leftRight.rawValue).\(weakSide)_behind",
                metrics: ["weak_kg": weak, "strong_kg": strong, "asymmetry": asym]
            ))
        }
        return findings
    }

    /// All findings: severity (severe first), then kind, then rule id.
    public func analyze(_ scores: [ScoreInput], unilateral: [UnilateralInput] = []) throws(StrengthModelError) -> [Finding] {
        for score in scores where !score.z.isFinite { throw .invalidInput("non-finite z for \(score.exerciseId)") }
        let all = try residualFindings(scores) + ratioFindings(scores) + leftRightFindings(unilateral)
        return all.enumerated().sorted { lhs, rhs in
            let (l, r) = (lhs.element, rhs.element)
            if l.severity != r.severity { return l.severity > r.severity }
            if l.kind.order != r.kind.order { return l.kind.order < r.kind.order }
            if l.ruleId != r.ruleId { return l.ruleId < r.ruleId }
            return lhs.offset < rhs.offset
        }.map(\.element)
    }
}

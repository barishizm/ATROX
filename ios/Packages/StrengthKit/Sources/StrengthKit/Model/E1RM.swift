import Foundation

/// An estimated one-rep max together with how much to trust it (docs/03-ML-MODEL.md §2, "güven ağırlığı").
public struct E1RMEstimate: Sendable, Equatable {
    public let valueKg: Double
    /// 0…1 from the bundle's confidence knots (1 for 1–5 effective reps, 0 from 30); × the no-RIR factor.
    public let confidence: Double

    public init(valueKg: Double, confidence: Double) {
        self.valueKg = valueKg
        self.confidence = confidence
    }
}

/// Rep → %1RM curve, f(1) = 1 (`gymml.models.e1rm.Curve`). The bundle ships the two-parameter general form.
public enum E1RMCurve: Sendable, Equatable {
    /// f(r) = 1 / (1 + ((r − 1)/k)^p)
    case general(k: Double, p: Double)
    /// Epley with (r − 1): the general form with p = 1.
    case epley(k: Double)
    /// f(r) = (a + 1 − r)/a
    case brzycki(a: Double)
    /// f(r) = r^(−b)
    case lombardi(b: Double)
    /// Mayhew / Wathan: (A + B e^(−c r)) / (A + B e^(−c)).
    case exponential(asymptote: Double, amplitude: Double, c: Double)

    /// Share of 1RM liftable for `reps` reps; reps clipped to [1, rMax].
    public func fraction(_ reps: Double, rMax: Double) -> Double {
        let r = min(max(reps, 1), rMax)
        switch self {
        case let .general(k, p): return 1 / (1 + pow(max(r - 1, 0) / k, p))
        case let .epley(k): return 1 / (1 + (r - 1) / k)
        case let .brzycki(a): return (a + 1 - r) / a
        case let .lombardi(b): return pow(r, -b)
        case let .exponential(asymptote, amplitude, c):
            return (asymptote + amplitude * exp(-c * r)) / (asymptote + amplitude * exp(-c))
        }
    }
}

/// Layer 1 of the score model: set → e1RM + confidence with category curves from `params.json`.
public struct E1RMModel: Sendable {
    public let params: E1RMParams

    public init(params: E1RMParams) {
        self.params = params
    }

    /// The model of the embedded base bundle. The bundle is a package resource covered by tests, so failing to read it
    /// is a build defect rather than a runtime condition.
    public static let standard: E1RMModel = {
        do {
            return try E1RMModel(params: EmbeddedModelBundle.params().e1rm)
        } catch {
            preconditionFailure("embedded model bundle unreadable: \(error)")
        }
    }()

    /// Curve category for a catalog movement pattern (`isolation_*` → `isolation`, unknown → default).
    public func category(for pattern: String?) -> String {
        guard let pattern else { return params.defaultCategory }
        if pattern.hasPrefix("isolation_") { return params.patternCategory["isolation_*"] ?? params.defaultCategory }
        return params.patternCategory[pattern] ?? params.defaultCategory
    }

    public func curve(for pattern: String?) -> E1RMCurve {
        let cat = params.categories[category(for: pattern)] ?? params.categories[params.defaultCategory]
        guard let cat else { return .general(k: 1, p: 1) }
        return .general(k: cat.k, p: cat.p)
    }

    /// c(r_eff): piecewise linear over the knots, 0 at/after the last knot, × no-RIR factor, 0 for warm-ups.
    public func confidence(effectiveReps: Double, rirKnown: Bool, isWarmup: Bool) -> Double {
        if isWarmup { return 0 }
        let xs = params.confidence.knotsReps, ys = params.confidence.knotsConf
        guard let last = xs.last, effectiveReps < last else { return 0 }
        var conf = ys[0]
        if effectiveReps > xs[0] {
            for idx in 1..<xs.count where effectiveReps <= xs[idx] {
                let frac = (effectiveReps - xs[idx - 1]) / (xs[idx] - xs[idx - 1])
                conf = ys[idx - 1] + frac * (ys[idx] - ys[idx - 1])
                break
            }
        }
        return rirKnown ? conf : conf * params.confidence.noRirFactor
    }

    /// e1RM and confidence of one set at `loadKg` (already the effective load). (0, 0) for unusable sets, like
    /// `gymml.scoring.score_set`.
    public func score(loadKg: Double, reps: Int, rir: Double?, isWarmup: Bool, pattern: String?) -> E1RMEstimate {
        guard loadKg > 0, loadKg.isFinite, reps >= 1 else { return E1RMEstimate(valueKg: 0, confidence: 0) }
        let effective = Double(reps) + (rir ?? 0)
        let value = loadKg / curve(for: pattern).fraction(effective, rMax: params.rMax)
        return E1RMEstimate(
            valueKg: value, confidence: confidence(effectiveReps: effective, rirKnown: rir != nil, isWarmup: isWarmup)
        )
    }

    /// e1RM of one logged set; nil for invalid input or when the set says nothing (confidence 0, e.g. ≥ 30 reps).
    public func estimate(weightKg: Double, reps: Int, rir: Int? = nil, pattern: String? = nil) -> E1RMEstimate? {
        guard (rir ?? 0) >= 0 else { return nil }
        let est = score(loadKg: weightKg, reps: reps, rir: rir.map(Double.init), isWarmup: false, pattern: pattern)
        return est.confidence > 0 ? est : nil
    }
}

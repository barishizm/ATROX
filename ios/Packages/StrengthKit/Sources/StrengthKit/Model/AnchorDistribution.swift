// swiftlint:disable identifier_name nesting
import Foundation

/// Competitor distribution of an anchor lift given sex, age and bodyweight (docs/03-ML-MODEL.md §4, §11).
/// The bundle's manifest decides the implementation; the scoring code only sees this protocol.
public protocol AnchorDistribution: Sendable {
    /// F(value | x).
    func cdf(lift: AnchorLift, sex: ModelSex, age: Double, bodyweightKg: Double, valueKg: Double) throws(StrengthModelError)
        -> Double
    /// Q(prob | x) in kg.
    func quantile(lift: AnchorLift, sex: ModelSex, age: Double, bodyweightKg: Double, prob: Double) throws(StrengthModelError)
        -> Double
}

/// Box-Cox Cole-Green (BCCG) / Box-Cox power exponential (BCPE) distributions, mirroring `gymml.models.boxcox`.
public struct BoxCoxDistribution: Sendable, Equatable {
    public enum Family: String, Sendable, Codable { case bccg = "BCCG", bcpe = "BCPE" }

    static let nuEpsilon = 1e-6

    public let family: Family
    public let mu: Double
    public let sigma: Double
    public let nu: Double
    public let tau: Double

    public init(family: Family, mu: Double, sigma: Double, nu: Double, tau: Double) {
        self.family = family
        self.mu = mu
        self.sigma = sigma
        self.nu = nu
        self.tau = tau
    }

    private var bound: Double { 1 / (sigma * max(abs(nu), Self.nuEpsilon)) }

    /// PE scale s = c·2^(1/τ), c² = 2^(−2/τ) Γ(1/τ)/Γ(3/τ).
    private var peScale: Double {
        let ln2 = log(2.0)
        let logC = 0.5 * ((-2 / tau) * ln2 + SpecialFunctions.logGamma(1 / tau) - SpecialFunctions.logGamma(3 / tau))
        return exp(logC + ln2 / tau)
    }

    private func tCDF(_ zv: Double) -> Double {
        switch family {
        case .bccg: return SpecialFunctions.normalCDF(zv)
        case .bcpe:
            let prob = SpecialFunctions.regularizedGammaP(1 / tau, pow(abs(zv / peScale), tau))
            return 0.5 + 0.5 * sign(zv) * prob
        }
    }

    private func tQuantile(_ uv: Double) -> Double {
        switch family {
        case .bccg: return SpecialFunctions.normalQuantile(uv)
        case .bcpe:
            let gv = SpecialFunctions.inverseRegularizedGammaP(1 / tau, abs(2 * uv - 1))
            return sign(uv - 0.5) * peScale * pow(gv, 1 / tau)
        }
    }

    private func sign(_ value: Double) -> Double { value > 0 ? 1 : (value < 0 ? -1 : 0) }

    public func cdf(_ y: Double) -> Double {
        guard y > 0 else { return 0 }
        let lr = log(y / mu)
        let zv = abs(nu) < Self.nuEpsilon ? lr / sigma : expm1(nu * lr) / (nu * sigma)
        let fb = tCDF(bound)
        let fz = tCDF(zv)
        let out = nu > 0 ? (fz - (1 - fb)) / fb : fz / fb
        return min(max(out, 0), 1)
    }

    public func quantile(_ prob: Double) -> Double {
        let fb = tCDF(bound)
        var uv = nu > 0 ? (1 - fb) + prob * fb : prob * fb
        uv = min(max(uv, 1e-300), 1 - 1e-16)
        let zv = tQuantile(uv)
        if abs(nu) < Self.nuEpsilon { return mu * exp(sigma * zv) }
        return mu * pow(max(1 + sigma * nu * zv, 1e-300), 1 / nu)
    }
}

/// Spline-LMS tables (`anchor_tables.json`): cubic tensor B-splines over age × log bodyweight per lift and sex.
public struct TableAnchorDistribution: AnchorDistribution {
    struct Tables: Codable {
        struct Links: Codable {
            let logSigma: [Double]
            let nu: [Double]
            let logTau: [Double]

            enum CodingKeys: String, CodingKey {
                case logSigma = "log_sigma", nu, logTau = "log_tau"
            }
        }

        struct Lift: Codable {
            let family: BoxCoxDistribution.Family
            let degree: Int
            let knotsAge: [Double]
            let knotsLogBw: [Double]
            /// sex → parameter (mu, sigma, nu, tau) → [age basis][bodyweight basis]
            let coef: [String: [String: [[Double]]]]
        }

        let format: String
        let links: Links
        let lifts: [String: Lift]
    }

    static let format = "atrox-anchor-tables/1"

    private let tables: Tables

    public init(data: Data) throws(StrengthModelError) {
        let tables: Tables = try decodeJSON(data)
        guard tables.format == Self.format else { throw .bundle("unsupported anchor tables format \(tables.format)") }
        for lift in AnchorLift.allCases {
            guard let table = tables.lifts[lift.rawValue] else { throw .missingParameter("anchor table \(lift.rawValue)") }
            for sex in ModelSex.allCases {
                guard let coef = table.coef[sex.rawValue], coef["mu"] != nil, coef["sigma"] != nil, coef["nu"] != nil else {
                    throw .missingParameter("anchor coefficients \(lift.rawValue)/\(sex.rawValue)")
                }
            }
        }
        self.tables = tables
    }

    /// Distribution parameters at x (inputs clipped to the knot range, as in training).
    public func distribution(lift: AnchorLift, sex: ModelSex, age: Double, bodyweightKg: Double) throws(StrengthModelError)
        -> BoxCoxDistribution {
        guard age.isFinite, bodyweightKg.isFinite, bodyweightKg > 0 else {
            throw .invalidInput("age/bodyweight must be finite and bodyweight positive")
        }
        guard let table = tables.lifts[lift.rawValue], let coef = table.coef[sex.rawValue] else {
            throw .missingParameter("anchor table \(lift.rawValue)/\(sex.rawValue)")
        }
        let ba = Self.basis(age, knots: table.knotsAge, degree: table.degree)
        let bb = Self.basis(log(bodyweightKg), knots: table.knotsLogBw, degree: table.degree)
        func eta(_ name: String) -> Double? {
            guard let grid = coef[name] else { return nil }
            var sum = 0.0
            for (ia, wa) in ba where wa != 0 {
                for (ib, wb) in bb where wb != 0 { sum += wa * grid[ia][ib] * wb }
            }
            return sum
        }
        let links = tables.links
        let tau = eta("tau").map { exp(Self.clamp($0, links.logTau)) } ?? 2
        return BoxCoxDistribution(
            family: table.family,
            mu: exp(eta("mu") ?? 0),
            sigma: exp(Self.clamp(eta("sigma") ?? 0, links.logSigma)),
            nu: Self.clamp(eta("nu") ?? 0, links.nu),
            tau: tau
        )
    }

    public func cdf(lift: AnchorLift, sex: ModelSex, age: Double, bodyweightKg: Double, valueKg: Double) throws(StrengthModelError)
        -> Double {
        try distribution(lift: lift, sex: sex, age: age, bodyweightKg: bodyweightKg).cdf(valueKg)
    }

    public func quantile(lift: AnchorLift, sex: ModelSex, age: Double, bodyweightKg: Double, prob: Double) throws(StrengthModelError)
        -> Double {
        try distribution(lift: lift, sex: sex, age: age, bodyweightKg: bodyweightKg).quantile(prob)
    }

    private static func clamp(_ value: Double, _ range: [Double]) -> Double {
        min(max(value, range[0]), range[1])
    }

    /// Non-zero B-spline basis values at x (clipped to [t_d, t_n]) as (index, value) pairs (Cox–de Boor).
    static func basis(_ value: Double, knots: [Double], degree: Int) -> [(Int, Double)] {
        let count = knots.count - degree - 1
        let x = min(max(value, knots[degree]), knots[count])
        var span = degree
        while span < count - 1, x >= knots[span + 1] { span += 1 }
        var values = [Double](repeating: 0, count: degree + 1)
        var left = [Double](repeating: 0, count: degree + 1)
        var right = [Double](repeating: 0, count: degree + 1)
        values[0] = 1
        for j in 1...degree {
            left[j] = x - knots[span + 1 - j]
            right[j] = knots[span + j] - x
            var saved = 0.0
            for r in 0..<j {
                let temp = values[r] / (right[r + 1] + left[j - r])
                values[r] = saved + right[r + 1] * temp
                saved = left[j - r] * temp
            }
            values[j] = saved
        }
        return (0...degree).map { (span - degree + $0, values[$0]) }
    }
}

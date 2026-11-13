// swiftlint:disable identifier_name nesting
import Foundation

/// Double-precision special functions used by the score model (pure Swift, Linux-safe).
public enum SpecialFunctions {
    /// Standard normal CDF Φ(x).
    public static func normalCDF(_ x: Double) -> Double {
        0.5 * erfc(-x / 2.0.squareRoot())
    }

    /// Standard normal quantile Φ⁻¹(p): Acklam's rational approximation refined with one Halley step
    /// (relative error ~1e-15). Returns ±infinity at 0 / 1 and NaN outside [0, 1].
    public static func normalQuantile(_ prob: Double) -> Double {
        guard prob > 0, prob < 1 else {
            if prob == 0 { return -.infinity }
            if prob == 1 { return .infinity }
            return .nan
        }
        let lowTail = 0.02425
        var x: Double
        if prob < lowTail {
            let q = (-2 * log(prob)).squareRoot()
            x = tailNumerator(q) / tailDenominator(q)
        } else if prob <= 1 - lowTail {
            let q = prob - 0.5
            let r = q * q
            x = centralNumerator(r) * q / centralDenominator(r)
        } else {
            let q = (-2 * log1p(-prob)).squareRoot()
            x = -tailNumerator(q) / tailDenominator(q)
        }
        // Halley refinement; the residual uses the complementary form in the upper tail for accuracy.
        let err = prob > 0.5 ? (1 - prob) - 0.5 * erfc(x / 2.0.squareRoot()) : normalCDF(x) - prob
        let u = err * (2 * Double.pi).squareRoot() * exp(x * x / 2)
        x -= u / (1 + x * u / 2)
        return x
    }

    private static func centralNumerator(_ r: Double) -> Double {
        ((((-3.969683028665376e+01 * r + 2.209460984245205e+02) * r - 2.759285104469687e+02) * r
            + 1.383577518672690e+02) * r - 3.066479806614716e+01) * r + 2.506628277459239e+00
    }

    private static func centralDenominator(_ r: Double) -> Double {
        ((((-5.447609879822406e+01 * r + 1.615858368580409e+02) * r - 1.556989798598866e+02) * r
            + 6.680131188771972e+01) * r - 1.328068155288572e+01) * r + 1
    }

    private static func tailNumerator(_ q: Double) -> Double {
        ((((-7.784894002430293e-03 * q - 3.223964580411365e-01) * q - 2.400758277161838e+00) * q
            - 2.549732539343734e+00) * q + 4.374664141464968e+00) * q + 2.938163982698783e+00
    }

    private static func tailDenominator(_ q: Double) -> Double {
        (((7.784695709041462e-03 * q + 3.224671290700398e-01) * q + 2.445134137142996e+00) * q
            + 3.754408661907416e+00) * q + 1
    }

    /// log Γ(x) for x > 0.
    public static func logGamma(_ x: Double) -> Double {
        lgamma(x)
    }

    /// Regularized lower incomplete gamma P(a, x), a > 0, x ≥ 0 (series / Lentz continued fraction).
    public static func regularizedGammaP(_ a: Double, _ x: Double) -> Double {
        guard x > 0 else { return 0 }
        guard x.isFinite else { return 1 }
        let logPrefix = a * log(x) - x - logGamma(a)
        if x < a + 1 {
            var term = 1 / a, sum = term, ap = a
            for _ in 0..<10_000 {
                ap += 1
                term *= x / ap
                sum += term
                if abs(term) < abs(sum) * 1e-17 { break }
            }
            return min(1, sum * exp(logPrefix))
        }
        let tiny = 1e-300
        var b = x + 1 - a, c = 1 / tiny, d = 1 / b, h = d
        for n in 1..<10_000 {
            let an = -Double(n) * (Double(n) - a)
            b += 2
            d = an * d + b
            if abs(d) < tiny { d = tiny }
            c = b + an / c
            if abs(c) < tiny { c = tiny }
            d = 1 / d
            let delta = d * c
            h *= delta
            if abs(delta - 1) < 1e-17 { break }
        }
        return max(0, 1 - exp(logPrefix) * h)
    }

    /// Inverse of P(a, ·): x with P(a, x) = p (Numerical Recipes `invgammp` start, Halley iterations).
    public static func inverseRegularizedGammaP(_ a: Double, _ prob: Double) -> Double {
        guard prob > 0 else { return 0 }
        guard prob < 1 else { return .infinity }
        let gln = logGamma(a)
        let a1 = a - 1
        var x: Double
        var lna1 = 0.0, afac = 0.0
        if a > 1 {
            lna1 = log(a1)
            afac = exp(a1 * (lna1 - 1) - gln)
            let pp = prob < 0.5 ? prob : 1 - prob
            let t = (-2 * log(pp)).squareRoot()
            var guess = (2.30753 + t * 0.27061) / (1 + t * (0.99229 + t * 0.04481)) - t
            if prob < 0.5 { guess = -guess }
            x = max(1e-3, a * pow(1 - 1 / (9 * a) - guess / (3 * a.squareRoot()), 3))
        } else {
            let t = 1 - a * (0.253 + a * 0.12)
            x = prob < t ? pow(prob / t, 1 / a) : 1 - log(1 - (prob - t) / (1 - t))
        }
        for _ in 0..<100 {
            if x <= 0 { return 0 }
            let err = regularizedGammaP(a, x) - prob
            let t = a > 1 ? afac * exp(-(x - a1) + a1 * (log(x) - lna1)) : exp(-x + a1 * log(x) - gln)
            guard t > 0 else { break }
            let u = err / t
            let step = u / (1 - 0.5 * min(1, u * (a1 / x - 1)))
            x -= step
            if x <= 0 { x = 0.5 * (x + step) }
            if abs(step) < 1e-15 * x { break }
        }
        return x
    }
}

import Foundation

/// Progress analytics (docs/03-ML-MODEL.md §9), a 1:1 port of `gymml.progress`. Input: one (day, e1RM kg) per
/// session; all slopes are on ln(e1RM) per day.
public struct ProgressAnalyzer: Sendable {
    public struct Session: Sendable, Equatable {
        public var day: Double
        public var e1rmKg: Double

        public init(day: Double, e1rmKg: Double) {
            self.day = day
            self.e1rmKg = e1rmKg
        }
    }

    public enum Status: String, Sendable { case ok, insufficientData = "insufficient_data" }

    public enum PlateauStatus: String, Sendable {
        case plateau, progressing, insufficientData = "insufficient_data"
    }

    public struct TheilSen: Sendable, Equatable {
        public var slope: Double
        public var intercept: Double
        public var slopeLow: Double
        public var slopeHigh: Double
        public var count: Int
    }

    public struct Trend: Sendable, Equatable {
        public var status: Status
        public var sessionCount: Int
        public var spanDays: Double
        public var fit: TheilSen?
        public var monthlyPct: Double?
        public var monthlyPctLow: Double?
        public var monthlyPctHigh: Double?
        public var sigma: Double?
        public var lastDay: Double?
    }

    public struct Score: Sendable, Equatable {
        public var status: Status
        public var score: Double?
        public var scoreLow: Double?
        public var scoreHigh: Double?
        public var ratio: Double?
        public var observedMonthlyPct: Double?
        public var expectedMonthlyPct: Double?
    }

    public struct Plateau: Sendable, Equatable {
        public var status: PlateauStatus
        public var windowCount: Int
        public var referenceCount: Int
        public var cusumMax: Double?
        public var sigma: Double?
    }

    public struct ForecastPoint: Sendable, Equatable {
        public var weeks: Double
        public var e1rmKg: Double
        public var low: Double
        public var high: Double
    }

    public struct Forecast: Sendable, Equatable {
        public var status: Status
        public var points: [ForecastPoint]
        public var slopeUsed: Double?
    }

    public struct Report: Sendable, Equatable {
        public var trend: Trend
        public var score: Score
        public var plateau: Plateau
        public var forecast: Forecast
    }

    static let daysPerWeek = 7.0

    public let params: ProgressParams

    public init(params: ProgressParams) {
        self.params = params
    }

    // MARK: Helpers

    static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        let mid = sorted.count / 2
        return sorted.count % 2 == 1 ? sorted[mid] : 0.5 * (sorted[mid - 1] + sorted[mid])
    }

    /// Drops non-finite or non-positive rows; sorted by day (stable).
    static func clean(_ sessions: [Session]) -> [Session] {
        sessions.filter { $0.day.isFinite && $0.e1rmKg.isFinite && $0.e1rmKg > 0 }
            .enumerated().sorted { ($0.element.day, $0.offset) < ($1.element.day, $1.offset) }.map(\.element)
    }

    /// Theil–Sen slope + Sen (1968) rank interval; pairs on the same day are skipped. nil with < 2 distinct days.
    static func theilSen(_ ts: [Double], _ ys: [Double], z: Double) -> TheilSen? {
        let count = ts.count
        var slopes: [Double] = []
        for i in 0..<count {
            for j in (i + 1)..<max(count, i + 1) where ts[j] != ts[i] {
                slopes.append((ys[j] - ys[i]) / (ts[j] - ts[i]))
            }
        }
        slopes.sort()
        guard !slopes.isEmpty else { return nil }
        let slope = median(slopes)
        let intercept = median(zip(ts, ys).map { $1 - slope * $0 })
        let total = Double(slopes.count), size = Double(count)
        let spread = z * (size * (size - 1) * (2 * size + 5) / 18).squareRoot()
        let lowRank = max(0, min(slopes.count - 1, Int(((total - spread) / 2).rounded(.down))))
        let highRank = max(0, min(slopes.count - 1, Int(((total + spread) / 2).rounded(.up)) - 1))
        return TheilSen(slope: slope, intercept: intercept, slopeLow: slopes[lowRank], slopeHigh: slopes[highRank], count: count)
    }

    private func monthlyPct(_ slope: Double) -> Double { exp(slope * params.daysPerMonth) - 1 }

    private func robustSigma(_ ts: [Double], _ ys: [Double], _ fit: TheilSen) -> Double {
        let resid = zip(ts, ys).map { $1 - (fit.intercept + fit.slope * $0) }
        let med = Self.median(resid)
        let mad = Self.median(resid.map { abs($0 - med) })
        return max(params.plateau.madToSigma * mad, params.plateau.sigmaFloor)
    }

    // MARK: Trend

    public func trend(_ sessions: [Session]) -> Trend {
        let tp = params.trend
        let data = Self.clean(sessions)
        guard let lastDay = data.last?.day else {
            return Trend(status: .insufficientData, sessionCount: 0, spanDays: 0)
        }
        let window = data.filter { $0.day >= lastDay - tp.windowWeeksMax * Self.daysPerWeek }
        let span = (window.last?.day ?? 0) - (window.first?.day ?? 0)
        let ts = window.map(\.day), ys = window.map { log($0.e1rmKg) }
        guard window.count >= tp.minSessions, span >= tp.minSpanWeeks * Self.daysPerWeek,
              let fit = Self.theilSen(ts, ys, z: tp.ciZ) else {
            return Trend(status: .insufficientData, sessionCount: window.count, spanDays: span)
        }
        return Trend(
            status: .ok, sessionCount: window.count, spanDays: span, fit: fit, monthlyPct: monthlyPct(fit.slope),
            monthlyPctLow: monthlyPct(fit.slopeLow), monthlyPctHigh: monthlyPct(fit.slopeHigh),
            sigma: robustSigma(ts, ys, fit), lastDay: lastDay
        )
    }

    // MARK: Expected gain and score

    /// Expected monthly e1RM gain for a level (0–100 percentile) and training age. The curve's numbers are assumptions.
    public func expectedMonthlyGain(percentile: Double, trainingYears: Double?) -> Double {
        let curve = params.expectedCurve
        let level = exp(-curve.levelDecay * min(max(percentile, 0), 100) / 100)
        let experience = trainingYears.map { 1 / (1 + max($0, 0) / curve.experienceHalfLifeYears) } ?? 1
        return curve.floorMonthlyGain + (curve.noviceMonthlyGain - curve.floorMonthlyGain) * level * experience
    }

    func scoreFromRatio(_ ratio: Double) -> Double {
        let xs = params.score.ratioAnchors, ys = params.score.scoreAnchors
        if ratio <= xs[0] { return ys[0] }
        if ratio >= xs[xs.count - 1] { return ys[ys.count - 1] }
        for idx in 1..<xs.count where ratio <= xs[idx] {
            return ys[idx - 1] + (ratio - xs[idx - 1]) / (xs[idx] - xs[idx - 1]) * (ys[idx] - ys[idx - 1])
        }
        return ys[ys.count - 1]
    }

    public func progressScore(_ trend: Trend, percentile: Double, trainingYears: Double?) -> Score {
        guard trend.status == .ok, let fit = trend.fit else { return Score(status: .insufficientData) }
        let gain = expectedMonthlyGain(percentile: percentile, trainingYears: trainingYears)
        let expectedLog = log1p(gain)
        func ratio(_ slope: Double) -> Double { slope * params.daysPerMonth / expectedLog }
        let mid = ratio(fit.slope)
        return Score(
            status: .ok, score: scoreFromRatio(mid), scoreLow: scoreFromRatio(ratio(fit.slopeLow)),
            scoreHigh: scoreFromRatio(ratio(fit.slopeHigh)), ratio: mid, observedMonthlyPct: trend.monthlyPct,
            expectedMonthlyPct: gain
        )
    }

    // MARK: Plateau

    /// Self-starting one-sided upper CUSUM over the last `windowWeeks` weeks against the running reference median.
    public func plateau(_ sessions: [Session]) -> Plateau {
        let pp = params.plateau
        let data = Self.clean(sessions)
        guard let lastDay = data.last?.day else { return Plateau(status: .insufficientData, windowCount: 0, referenceCount: 0) }
        let windowStart = lastDay - pp.windowWeeks * Self.daysPerWeek
        let refStart = windowStart - pp.referenceWeeks * Self.daysPerWeek
        let window = data.filter { $0.day > windowStart }
        let reference = data.filter { refStart < $0.day && $0.day <= windowStart }
        guard Double(window.count) >= pp.minSessionsPerWeek * pp.windowWeeks, reference.count >= pp.referenceMinSessions else {
            return Plateau(status: .insufficientData, windowCount: window.count, referenceCount: reference.count)
        }
        let recent = reference + window
        let ts = recent.map(\.day), ys = recent.map { log($0.e1rmKg) }
        guard let fit = Self.theilSen(ts, ys, z: params.trend.ciZ) else {
            return Plateau(status: .insufficientData, windowCount: window.count, referenceCount: reference.count)
        }
        let sigma = robustSigma(ts, ys, fit)
        var prev = reference.map { log($0.e1rmKg) }
        var cusum = 0.0, cusumMax = 0.0
        for session in window {
            let x = log(session.e1rmKg)
            let scale = sigma * (1 + pp.medianVarianceFactor / Double(prev.count)).squareRoot()
            let zv = min((x - Self.median(prev)) / scale, pp.clipZ)
            cusum = max(0, cusum + zv - pp.k)
            cusumMax = max(cusumMax, cusum)
            prev.append(x)
        }
        return Plateau(
            status: cusumMax >= pp.h ? .progressing : .plateau, windowCount: window.count, referenceCount: reference.count,
            cusumMax: cusumMax, sigma: sigma
        )
    }

    // MARK: Forecast

    /// 4/8/12-week e1RM forecast: damped, clipped trend with a band that widens over time.
    public func forecast(_ trend: Trend, percentile: Double, trainingYears: Double?, horizonsWeeks: [Double]? = nil)
        throws(StrengthModelError) -> Forecast {
        let fp = params.forecast
        let horizons = horizonsWeeks ?? fp.horizonsWeeks
        for weeks in horizons where !(weeks > 0 && weeks <= fp.maxHorizonWeeks) {
            throw .invalidInput("forecast horizon \(weeks) outside (0, \(fp.maxHorizonWeeks)] weeks")
        }
        guard trend.status == .ok, let fit = trend.fit, let lastDay = trend.lastDay, let sigma = trend.sigma else {
            return Forecast(status: .insufficientData, points: [])
        }
        let dpm = params.daysPerMonth
        let expectedLog = log1p(expectedMonthlyGain(percentile: percentile, trainingYears: trainingYears))
        let slope = min(max(fit.slope, log1p(-fp.maxMonthlyLoss) / dpm), fp.maxRatioToExpected * expectedLog / dpm)
        let ciZ = params.trend.ciZ
        let slopeSE = (fit.slopeHigh - fit.slopeLow) / (2 * ciZ)
        let level = fit.intercept + fit.slope * lastDay
        let points = horizons.map { weeks -> ForecastPoint in
            let eff = fp.dampingDays * (1 - exp(-weeks * Self.daysPerWeek / fp.dampingDays))
            let mid = level + slope * eff
            let half = ciZ * (sigma * sigma + (slopeSE * eff) * (slopeSE * eff)).squareRoot()
            return ForecastPoint(weeks: weeks, e1rmKg: exp(mid), low: exp(mid - half), high: exp(mid + half))
        }
        return Forecast(status: .ok, points: points, slopeUsed: slope)
    }

    public func analyze(_ sessions: [Session], percentile: Double, trainingYears: Double?) throws(StrengthModelError) -> Report {
        let tr = trend(sessions)
        return try Report(
            trend: tr, score: progressScore(tr, percentile: percentile, trainingYears: trainingYears), plateau: plateau(sessions),
            forecast: forecast(tr, percentile: percentile, trainingYears: trainingYears)
        )
    }
}

extension ProgressAnalyzer.Trend {
    init(status: ProgressAnalyzer.Status, sessionCount: Int, spanDays: Double) {
        self.init(
            status: status, sessionCount: sessionCount, spanDays: spanDays, fit: nil, monthlyPct: nil, monthlyPctLow: nil,
            monthlyPctHigh: nil, sigma: nil, lastDay: nil
        )
    }
}

extension ProgressAnalyzer.Score {
    init(status: ProgressAnalyzer.Status) {
        self.init(status: status, score: nil, scoreLow: nil, scoreHigh: nil, ratio: nil, observedMonthlyPct: nil, expectedMonthlyPct: nil)
    }
}

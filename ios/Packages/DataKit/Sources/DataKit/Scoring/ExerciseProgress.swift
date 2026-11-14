import Foundation
import StrengthKit

/// Everything the e1RM chart of one exercise shows (P068): sessions with record flags, the trend line, the
/// 4/8/12-week forecast band, plateau zones and the progress score.
public struct ExerciseProgress: Sendable, Equatable {
    public var exerciseId: String
    public var points: [ProgressPoint]
    public var trend: ProgressAnalyzer.Trend
    public var trendLine: [TrendPoint]
    public var forecast: [ForecastBand]
    public var plateauZones: [PlateauZone]
    public var plateau: ProgressAnalyzer.PlateauStatus
    public var score: ProgressAnalyzer.Score
    public var today: Int
}

extension ScoreService {
    /// Best e1RM per training day of one exercise; only sets the e1RM model trusts count (same bar as the score).
    static func progressSessions(
        _ sets: [ScoredSet], exercise: TaxonomyExercise, model: StrengthModel, user: ScoringUser
    ) -> [ProgressAnalyzer.Session] {
        let minimum = model.params.currentStrength.minSetConfidence
        var best: [Int: Double] = [:]
        for item in sets where !item.set.isWarmup {
            guard let estimate = try? model.scoreSet(exercise, item.set, user: user), estimate.confidence >= minimum,
                  estimate.valueKg.isFinite, estimate.valueKg > 0 else { continue }
            best[item.set.day] = max(best[item.set.day] ?? 0, estimate.valueKg)
        }
        return best.keys.sorted().map { ProgressAnalyzer.Session(day: Double($0), e1rmKg: best[$0] ?? 0) }
    }

    /// e1RM history, trend, forecast, plateau zones and progress score of one exercise; nil when it cannot be scored.
    public func exerciseProgress(userId: UUID, exerciseId: String, population: ReferencePopulation) async -> ExerciseProgress? {
        guard let scoring = await currentScoringModel(), case .success(let user) = currentUser(userId: userId) else { return nil }
        let id = ScoreCalculator.scoringId(exerciseId)
        let model = scoring.model
        guard let exercise = model.exercises[id], exercise.scoringType != "reps_only",
              let sets = (try? loadScoredSets(userId: userId, exerciseIds: [id]))?[id], !sets.isEmpty else { return nil }
        let today = ScoreCalculator.dayNumber(currentDate(), calendar: currentCalendar)
        let sessions = Self.progressSessions(sets, exercise: exercise, model: model, user: user)
        guard !sessions.isEmpty else { return nil }
        let percentile = ScoreCalculator.evaluate(id, sets: sets, model: model, user: user, population: population, asOfDay: today)?.score.score ?? 50
        return Self.progress(id, sessions: sessions, params: model.params.progress, percentile: percentile, trainingYears: nil, today: today, calendar: currentCalendar)
    }

    static func progress(
        _ id: String, sessions: [ProgressAnalyzer.Session], params: ProgressParams, percentile: Double, trainingYears: Double?,
        today: Int, calendar: Calendar
    ) -> ExerciseProgress {
        let analyzer = ProgressAnalyzer(params: params)
        let trend = analyzer.trend(sessions)
        let forecast = try? analyzer.forecast(trend, percentile: percentile, trainingYears: trainingYears)
        let points = ProgressSeries.points(sessions, calendar: calendar)
        var line: [TrendPoint] = []
        if let last = points.last, let first = points.first {
            let windowStart = max(first.day, last.day - Int((params.trend.windowWeeksMax * 7).rounded()))
            line = ProgressSeries.trendLine(trend, window: windowStart...last.day, calendar: calendar)
        }
        return ExerciseProgress(
            exerciseId: id, points: points, trend: trend, trendLine: line,
            forecast: points.last.flatMap { last in forecast.map { ProgressSeries.forecastBands($0, lastDay: last.day, calendar: calendar) } } ?? [],
            plateauZones: ProgressSeries.plateauZones(sessions, analyzer: analyzer),
            plateau: analyzer.plateau(sessions).status,
            score: analyzer.progressScore(trend, percentile: percentile, trainingYears: trainingYears), today: today
        )
    }
}

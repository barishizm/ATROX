import DataKit
import DesignSystem
import Foundation
import Observation
import StrengthKit

/// State of the progress charts of the Analysis tab (P068): e1RM per exercise with trend and forecast, score over
/// time, weekly volume, the training calendar and bodyweight with relative strength. All series come ready-made from
/// DataKit; this model only picks the range, the exercise and the unit.
@MainActor
@Observable
final class ProgressModel {
    struct ExerciseOption: Identifiable, Equatable {
        let id: String
        let name: String
    }

    enum ScoreScope: String, CaseIterable, Identifiable {
        case overall, exercise, muscle
        var id: String { rawValue }
    }

    /// "Faster / slower than expected for your level".
    enum Pace: Equatable {
        case faster, onTrack, slower, unknown
    }

    private(set) var isLoading = true
    private(set) var exercises: [ExerciseOption] = []
    private(set) var progress: ExerciseProgress?
    private(set) var scoreSeries: [ScorePoint] = []
    private(set) var volume: [WeekVolume] = []
    private(set) var calendarCells: [CalendarCell] = []
    private(set) var bodyweight: [BodyweightPoint] = []
    private(set) var muscles: [String] = []
    private(set) var unavailable: ScoreUnavailable?

    var range: ChartRange = .halfYear {
        didSet { if range != oldValue, !suppress { Task { await reloadRangeDependent() } } }
    }

    var exerciseId: String? {
        didSet { if exerciseId != oldValue, !suppress { Task { await reloadExercise() } } }
    }

    var scoreScope: ScoreScope = .overall {
        didSet { if scoreScope != oldValue, !suppress { Task { await reloadScore() } } }
    }

    var muscle: String? {
        didSet { if muscle != oldValue, !suppress { Task { await reloadScore() } } }
    }

    let context: HistoryContext
    @ObservationIgnored private let center: ScoreCenter
    @ObservationIgnored private let stats: TrainingStats
    @ObservationIgnored private let calendar: Calendar
    @ObservationIgnored private var names: [String: String] = [:]
    /// Set while `load()` fills the selections itself, so the property observers do not start their own reloads.
    @ObservationIgnored private var suppress = false

    /// Points kept on a line chart; longer series are thinned (records always stay).
    static let maxChartPoints = 160

    init(context: HistoryContext, center: ScoreCenter, stats: TrainingStats, calendar: Calendar = .current) {
        self.context = context
        self.center = center
        self.stats = stats
        self.calendar = calendar
    }

    var unit: WeightUnit { context.unit }
    var locale: Locale { context.locale }
    var today: Int { ScoreCalculator.dayNumber(Date(), calendar: calendar) }
    var population: ReferencePopulation { center.overview?.population ?? .gym }
    var hasData: Bool { !exercises.isEmpty }

    var exerciseName: String { exerciseId.flatMap { names[$0] } ?? "" }

    // MARK: Loading

    func load() async {
        suppress = true
        defer { suppress = false }
        names = await context.loadNames()
        let overview = center.overview
        unavailable = overview == nil ? center.unavailable : nil
        exercises = (overview?.exercises.keys.sorted() ?? [])
            .map { ExerciseOption(id: $0, name: names[$0] ?? $0) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        muscles = (overview?.muscles.keys.sorted() ?? [])
        if muscle == nil || !muscles.contains(muscle ?? "") { muscle = muscles.first }
        if exerciseId == nil || !exercises.contains(where: { $0.id == exerciseId }) {
            exerciseId = Self.defaultExercise(overview: overview)
        }
        async let calendarDays = stats.workoutCalendar(userId: context.userId)
        async let weights = stats.bodyweightHistory(userId: context.userId)
        calendarCells = FrequencyCalendar.cells(workouts: await calendarDays, today: today, months: 6, calendar: calendar)
        bodyweight = await weights
        await reloadRangeDependent()
        await reloadExercise()
        await reloadScore()
        isLoading = false
    }

    private func reloadExercise() async {
        guard let id = exerciseId else {
            progress = nil
            return
        }
        progress = await center.service.exerciseProgress(userId: context.userId, exerciseId: id, population: population)
        if scoreScope == .exercise { await reloadScore() }
    }

    private func reloadScore() async {
        let key: String?
        let scope: SnapshotScope
        switch scoreScope {
        case .overall: (scope, key) = (.overall, "overall")
        case .exercise: (scope, key) = (.exercise, exerciseId)
        case .muscle: (scope, key) = (.muscle, muscle)
        }
        guard let key else {
            scoreSeries = []
            return
        }
        let rows = await center.service.history(userId: context.userId, scope: scope, key: key, population: population)
        scoreSeries = rows.map { ScorePoint(date: $0.date, score: $0.score) }
    }

    private func reloadRangeDependent() async {
        volume = await stats.weeklyVolume(userId: context.userId, weeks: Self.volumeWeeks(range))
    }

    // MARK: Derived series (pure helpers below are unit tested)

    var rangeStartDate: Date? { range.startDay(today: today).map { ScoreCalculator.date(ofDay: $0, calendar: calendar) } }

    /// e1RM sessions inside the range, thinned for smooth drawing.
    var e1rmPoints: [ProgressPoint] {
        guard let progress else { return [] }
        let inRange = SeriesTools.filter(progress.points, day: \.day, range: range, today: today)
        return SeriesTools.thin(inRange, limit: Self.maxChartPoints, value: \.e1rmKg, keep: \.isRecord)
    }

    var plateauZones: [PlateauZone] {
        guard let progress, let start = range.startDay(today: today) else { return progress?.plateauZones ?? [] }
        return progress.plateauZones.filter { $0.endDay >= start }.map { PlateauZone(startDay: max($0.startDay, start), endDay: $0.endDay) }
    }

    var scorePoints: [ScorePoint] {
        let inRange = scoreSeries.filter { range.contains(day: ScoreCalculator.dayNumber($0.date, calendar: calendar), today: today) }
        return SeriesTools.thin(inRange, limit: Self.maxChartPoints, value: \.score)
    }

    var relativePoints: [RelativePoint] {
        guard let progress else { return [] }
        let inRange = SeriesTools.filter(progress.points, day: \.day, range: range, today: today)
        return SeriesTools.thin(RelativeStrength.series(inRange, bodyweights: bodyweight), limit: Self.maxChartPoints, value: \.ratio)
    }

    var bodyweightPoints: [BodyweightPoint] {
        SeriesTools.thin(SeriesTools.filter(bodyweight, day: \.day, range: range, today: today), limit: Self.maxChartPoints, value: \.weightKg)
    }

    var pace: Pace { progress.map { Self.pace($0.score) } ?? .unknown }

    var observedPercentText: String? { progress?.score.observedMonthlyPct.map { Self.percentText($0, locale: locale) } }
    var expectedPercentText: String? { progress?.score.expectedMonthlyPct.map { Self.percentText($0, locale: locale) } }

    // MARK: Display helpers

    func displayWeight(_ kg: Double) -> Double { unit.value(fromKilograms: kg) }
    func weightText(_ kg: Double) -> String { context.weightText(kg) }

    func dateText(_ date: Date) -> String { date.formatted(.dateTime.day().month(.abbreviated).year().locale(locale)) }

    // MARK: Pure helpers

    /// Weeks of volume shown for a range (the "all" view caps at two years).
    nonisolated static func volumeWeeks(_ range: ChartRange) -> Int {
        switch range {
        case .month: 5
        case .quarter: 13
        case .halfYear: 26
        case .year: 52
        case .all: 104
        }
    }

    /// Progress score 50 = as expected for the level. Bands of ten points around it count as on track.
    nonisolated static func pace(_ score: ProgressAnalyzer.Score) -> Pace {
        score.status == .ok ? pace(value: score.score) : .unknown
    }

    nonisolated static func pace(value: Double?) -> Pace {
        guard let value else { return .unknown }
        if value >= 60 { return .faster }
        if value <= 40 { return .slower }
        return .onTrack
    }

    /// "+2,3 %" (a fraction in, percent text out).
    nonisolated static func percentText(_ fraction: Double, locale: Locale) -> String {
        let value = fraction * 100
        let number = abs(value).formatted(.number.precision(.fractionLength(0...1)).locale(locale))
        return (value < 0 ? "−" : "+") + number + " %"
    }

    /// The point nearest in time to where the finger is (chart value reading).
    nonisolated static func nearest<T>(_ items: [T], to date: Date, at keyPath: KeyPath<T, Date>) -> T? {
        items.min { abs($0[keyPath: keyPath].timeIntervalSince(date)) < abs($1[keyPath: keyPath].timeIntervalSince(date)) }
    }

    /// The exercise with the newest deciding set; ties by id.
    nonisolated static func defaultExercise(overview: ScoreOverview?) -> String? {
        guard let overview else { return nil }
        return overview.exercises.keys.sorted().max {
            let lhs = overview.exercises[$0]?.basis?.day ?? 0, rhs = overview.exercises[$1]?.basis?.day ?? 0
            return lhs != rhs ? lhs < rhs : $0 > $1
        }
    }
}

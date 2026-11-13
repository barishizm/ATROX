import DataKit
import DesignSystem
import Foundation
import Observation
import StrengthKit

/// Percent sentence helpers. Turkish attaches the ablative case to the spoken number ("%73'ünden"), which depends on
/// its last word, so the suffix is computed instead of translated.
enum ScoreSentence {
    /// Suffix (with apostrophe) of "<n>'den/dan/…" in the possessive form used after "%": "%73'ünden", "%40'ından".
    static func turkishPossessiveAblative(_ number: Int) -> String {
        let units: [Int: String] = [
            1: "'inden", 2: "'sinden", 3: "'ünden", 4: "'ünden", 5: "'inden", 6: "'sından", 7: "'sinden", 8: "'inden", 9: "'undan",
        ]
        let tens: [Int: String] = [
            1: "'undan", 2: "'sinden", 3: "'undan", 4: "'ından", 5: "'sinden", 6: "'ından", 7: "'inden", 8: "'inden", 9: "'ından",
        ]
        let value = min(max(number, 0), 100)
        if value == 100 { return "'ünden" }
        if value == 0 { return "'dan" }
        if value % 10 != 0 { return units[value % 10] ?? "'inden" }
        return tens[value / 10] ?? "'inden"
    }
}

/// State of the exercise score screen (P065) for one exercise and one reference group at a time.
@MainActor
@Observable
final class ExerciseScoreModel {
    enum State: Equatable {
        case loading
        case ready(ExerciseInsight)
        case unavailable(ScoreUnavailable)
        case failed
    }

    struct DensityPoint: Identifiable, Equatable {
        let x: Double
        let y: Double
        var id: Double { x }
    }

    struct Marker: Identifiable, Equatable {
        let id: String
        let x: Double
        let level: ScoreLevel
    }

    struct Target: Equatable {
        let level: ScoreLevel
        let minScore: Int
        let e1rmText: String
        let gapText: String
        /// "5 × 82,5 kg" per offered rep count; loads are rounded UP to the next loadable step.
        let loads: [String]
    }

    let exerciseID: String
    let userId: UUID
    let unit: WeightUnit
    let locale: Locale
    let languageCode: String
    private(set) var state: State = .loading
    private(set) var name = ""
    var population: ReferencePopulation
    @ObservationIgnored private let service: ScoreService
    @ObservationIgnored private let nameProvider: @Sendable () async -> String

    init(
        exerciseID: String, userId: UUID, service: ScoreService, population: ReferencePopulation, unit: WeightUnit, locale: Locale,
        languageCode: String, name: @escaping @Sendable () async -> String = { "" }
    ) {
        self.exerciseID = exerciseID
        self.userId = userId
        self.service = service
        self.population = population
        self.unit = unit
        self.locale = locale
        self.languageCode = languageCode
        self.nameProvider = name
    }

    // MARK: Loading

    func load() async {
        name = await nameProvider()
        await reload()
    }

    /// Group switcher: recomputes straight from the history, nothing is stored.
    func select(_ group: ReferencePopulation) async {
        guard group != population else { return }
        population = group
        await reload()
    }

    private func reload() async {
        guard let insight = await service.insight(userId: userId, exerciseId: exerciseID, population: population) else {
            switch await service.overview(userId: userId, population: population) {
            case .unavailable(let reason): state = .unavailable(reason)
            case .ready: state = .failed
            }
            return
        }
        state = .ready(insight)
    }

    // MARK: Derived values

    var insight: ExerciseInsight? {
        if case .ready(let insight) = state { return insight }
        return nil
    }

    var score: Double? { insight?.evaluation?.score.score }

    /// Whole percent beaten, 1…99.
    var percentile: Int? { score.map { min(max(Int($0.rounded()), 1), 99) } }

    var levelName: String? {
        score.map { ScoreLevel(score: $0).localizedName(locale: locale) }
    }

    /// Turkish suffix of the sentence's number; empty in English.
    var sentenceSuffix: String {
        guard languageCode == "tr", let percentile else { return "" }
        return ScoreSentence.turkishPossessiveAblative(percentile)
    }

    var sentenceKey: String {
        switch population {
        case .gym: "gym"
        case .general: "general"
        case .competitor: "competitor"
        }
    }

    func weightText(_ kg: Double) -> String { WeightFormat.string(kilograms: kg, unit: unit, locale: locale) }

    /// Chart x unit symbol.
    var axisUnit: String { unit.symbol }

    /// Density curve in the display unit (density per displayed unit, so the area stays 1).
    var densityPoints: [DensityPoint] {
        guard let distribution = insight?.distribution else { return [] }
        let kgPerUnit = unit.kilograms(from: 1)
        return distribution.points.map { DensityPoint(x: unit.value(fromKilograms: $0.e1rmKg), y: $0.density * kgPerUnit) }
    }

    var userX: Double? { insight?.evaluation?.strength.e1rmKg.map(unit.value(fromKilograms:)) }
    var medianX: Double? { insight?.distribution.map { unit.value(fromKilograms: $0.median) } }

    var levelMarkers: [Marker] {
        (insight?.distribution?.levels ?? []).compactMap { marker in
            guard let level = ScoreLevel.allCases.first(where: { $0.localizationKey.hasSuffix(".\(marker.key)") }) else { return nil }
            return Marker(id: marker.key, x: unit.value(fromKilograms: marker.e1rmKg), level: level)
        }
    }

    /// Uncertainty band on the x axis.
    var bandX: ClosedRange<Double>? {
        insight?.bandE1RMKg.map { unit.value(fromKilograms: $0.lowerBound)...unit.value(fromKilograms: $0.upperBound) }
    }

    var target: Target? {
        guard let insight, let next = insight.nextTarget else { return nil }
        let level = ScoreLevel.allCases.first { $0.localizationKey.hasSuffix(".\(next.level)") } ?? ScoreLevel(score: next.minScore)
        return Target(
            level: level, minScore: Int(next.minScore.rounded()), e1rmText: weightText(next.e1rmKg), gapText: weightText(next.gapKg),
            loads: insight.targetLoads.map { "\($0.reps) × \(weightText(PlateRounding.up(kilograms: $0.weightKg, unit: unit)))" }
        )
    }

    /// "80 kg × 6 · e1RM 94 kg · 12 Nov" of the set that decides the score.
    var basisText: String? {
        guard let basis = insight?.evaluation?.basis else { return nil }
        let date = ScoreCalculator.date(ofDay: basis.day).formatted(.dateTime.day().month(.abbreviated).year().locale(locale))
        return "\(weightText(basis.weightKg)) × \(basis.reps) · e1RM \(weightText(basis.e1rmKg)) · \(date)"
    }

    var confidence: ScoreConfidence? { insight?.evaluation?.score.confidence }
    var reasons: [ConfidenceReason] { insight?.reasons ?? [] }
    var isMachine: Bool { insight?.evaluation?.score.isMachine ?? false }
}

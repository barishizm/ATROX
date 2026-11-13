import DataKit
import DesignSystem
import Foundation
import Observation
import StrengthKit

/// State of the Analysis tab's muscle views (P066): a front/back heat map in two modes, and the same data as a list.
@MainActor
@Observable
final class MuscleAnalysisModel {
    enum Mode: String, CaseIterable, Identifiable {
        case score, load
        var id: String { rawValue }
    }

    struct Row: Identifiable, Equatable {
        let muscle: Muscle
        /// nil = no scored exercise trains this muscle yet.
        let score: Double?
        /// Weighted sets in the last 7 days.
        let sets: Double
        /// Score change over the last 4 weeks.
        let change: Double?
        let isWeak: Bool
        var id: Muscle { muscle }
    }

    private(set) var isLoading = true
    private(set) var rows: [Row] = []
    private(set) var unavailable: ScoreUnavailable?
    var mode: Mode = .score

    let userId: UUID
    @ObservationIgnored private let center: ScoreCenter
    @ObservationIgnored private let stats: TrainingStats

    init(userId: UUID, center: ScoreCenter, stats: TrainingStats) {
        self.userId = userId
        self.center = center
        self.stats = stats
    }

    func load() async {
        let report = await stats.muscleReport(userId: userId)
        let population = center.overview?.population ?? .gym
        let changes = await stats.muscleChanges(userId: userId, population: population)
        rows = Self.rows(overview: center.overview, report: report, changes: changes)
        unavailable = center.overview == nil ? center.unavailable : nil
        isLoading = false
    }

    /// All 17 muscles. The weakest three are flagged once more than three muscles have a score.
    nonisolated static func rows(overview: ScoreOverview?, report: MuscleReport, changes: [String: Double]) -> [Row] {
        let scores = (overview?.muscles ?? [:]).mapValues(\.score)
        let weak = Set(MuscleRanking.weakest(scores))
        return Muscle.allCases.map { muscle in
            Row(
                muscle: muscle, score: scores[muscle.rawValue], sets: report.last7Days[muscle.rawValue] ?? 0,
                change: changes[muscle.rawValue], isWeak: weak.contains(muscle.rawValue)
            )
        }
    }

    /// Map colors: score / 100 in score mode, share of the busiest muscle in load mode.
    var intensities: [Muscle: Double] {
        switch mode {
        case .score: Dictionary(uniqueKeysWithValues: rows.compactMap { row in row.score.map { (row.muscle, $0 / 100) } })
        case .load: MuscleIntensities.heatmap(Dictionary(uniqueKeysWithValues: rows.map { ($0.muscle, $0.sets) }))
        }
    }

    /// Score mode: scored muscles best first, then unscored ones. Load mode: the most neglected first.
    var listRows: [Row] {
        Self.sorted(rows, mode: mode)
    }

    nonisolated static func sorted(_ rows: [Row], mode: Mode) -> [Row] {
        switch mode {
        case .score:
            rows.sorted {
                switch ($0.score, $1.score) {
                case let (lhs?, rhs?): (lhs, $1.muscle.rawValue) > (rhs, $0.muscle.rawValue)
                case (_?, nil): true
                case (nil, _?): false
                case (nil, nil): $0.muscle.rawValue < $1.muscle.rawValue
                }
            }
        case .load:
            rows.sorted { ($0.sets, $0.muscle.rawValue) < ($1.sets, $1.muscle.rawValue) }
        }
    }

    var hasScores: Bool { rows.contains { $0.score != nil } }
    var hasLoad: Bool { rows.contains { $0.sets > 0 } }
}

/// State of one muscle's detail page.
@MainActor
@Observable
final class MuscleDetailModel {
    private(set) var isLoading = true
    private(set) var detail: MuscleDetail?
    private(set) var weeklySets: [Double] = Array(repeating: 0, count: 4)
    private(set) var last7Days = 0.0
    private(set) var change: Double?
    private(set) var names: [String: String] = [:]

    let muscle: Muscle
    let userId: UUID
    @ObservationIgnored private let service: ScoreService
    @ObservationIgnored private let stats: TrainingStats
    @ObservationIgnored private let center: ScoreCenter
    @ObservationIgnored private let nameProvider: @Sendable () async -> [String: String]

    init(
        muscle: Muscle, userId: UUID, service: ScoreService, stats: TrainingStats, center: ScoreCenter,
        names: @escaping @Sendable () async -> [String: String]
    ) {
        self.muscle = muscle
        self.userId = userId
        self.service = service
        self.stats = stats
        self.center = center
        nameProvider = names
    }

    func load() async {
        names = await nameProvider()
        let report = await stats.muscleReport(userId: userId)
        weeklySets = report.weekly[muscle.rawValue] ?? Array(repeating: 0, count: 4)
        last7Days = report.last7Days[muscle.rawValue] ?? 0
        let population = center.overview?.population ?? .gym
        change = await stats.muscleChanges(userId: userId, population: population)[muscle.rawValue]
        detail = await service.muscleDetail(userId: userId, muscle: muscle.rawValue)
        isLoading = false
    }

    var score: Double? { detail?.score?.score }

    /// Weeks oldest → newest, labelled by how many weeks ago they ended (3, 2, 1, 0).
    var weeklyBars: [(weeksAgo: Int, sets: Double)] {
        weeklySets.enumerated().map { (weeksAgo: weeklySets.count - 1 - $0.offset, sets: $0.element) }
    }

    func name(of exerciseId: String) -> String { names[exerciseId] ?? exerciseId }
}

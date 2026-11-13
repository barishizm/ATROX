import Foundation

/// The four kinds of personal record (P040).
public enum RecordMetric: String, Sendable, CaseIterable {
    /// Heaviest weight lifted for at least one rep.
    case weight
    /// Most reps at a given weight (a set counts when no earlier set with the same or a heavier weight had as many).
    case reps
    /// Highest estimated one-rep max.
    case e1rm
    /// Highest volume (weight × reps) in a single set.
    case volume

    /// Which badge to show when one set breaks several records at once (lower is more important).
    public var priority: Int {
        switch self {
        case .weight: 0
        case .e1rm: 1
        case .volume: 2
        case .reps: 3
        }
    }
}

/// A set as the record engine sees it. Only completed, non-warm-up sets are passed in.
public struct RecordSet: Sendable, Equatable {
    public let id: UUID
    /// Chronological position: sets are replayed ordered by `(date, order)`.
    public let date: Date
    public let order: Int
    public let weightKg: Double
    public let reps: Int
    public let rir: Int?

    public init(id: UUID, date: Date, order: Int = 0, weightKg: Double, reps: Int, rir: Int? = nil) {
        self.id = id
        self.date = date
        self.order = order
        self.weightKg = weightKg
        self.reps = reps
        self.rir = rir
    }
}

/// One standing record. `weightKg` matters for `.reps` (the weight the reps were done at).
public struct RecordMark: Sendable, Equatable {
    public let metric: RecordMetric
    public let value: Double
    public let setId: UUID
    public let date: Date
    public let weightKg: Double

    public init(metric: RecordMetric, value: Double, setId: UUID, date: Date, weightKg: Double) {
        self.metric = metric
        self.value = value
        self.setId = setId
        self.date = date
        self.weightKg = weightKg
    }
}

/// A record a set breaks.
public struct RecordBreak: Sendable, Equatable {
    public let metric: RecordMetric
    public let value: Double
    /// The standing value it beat.
    public let previousValue: Double
    /// Whether the new value is more than `RecordMath.outlierFactor` above the previous best (typo guard).
    public let isOutlier: Bool
}

/// The result of replaying a history.
public struct RecordReplay: Sendable, Equatable {
    /// Standing records: one each for weight, e1RM and volume, plus the Pareto front for reps.
    public let board: [RecordMark]
    /// Per set id, the records it broke *after* the exercise had a first entry. The very first set of an exercise
    /// ("ilk kayıt") sets the board but breaks nothing.
    public let breaks: [UUID: [RecordBreak]]
}

public enum RecordMath {
    /// A new e1RM more than 12% above the previous best asks "Did you enter this set correctly?" first.
    public static let outlierFactor = 1.12

    /// Numeric value of a set for one metric; nil when the set cannot take part (e.g. bodyweight sets have no weight).
    public static func value(_ metric: RecordMetric, of set: RecordSet) -> Double? {
        guard set.reps >= 1, set.weightKg >= 0, set.weightKg.isFinite else { return nil }
        switch metric {
        case .weight: return set.weightKg > 0 ? set.weightKg : nil
        case .reps: return Double(set.reps)
        case .volume: return set.weightKg > 0 ? set.weightKg * Double(set.reps) : nil
        case .e1rm: return E1RMModel.standard.estimate(weightKg: set.weightKg, reps: set.reps, rir: set.rir)?.valueKg
        }
    }

    /// Records `set` would break against a standing `board`. Empty when the board is empty (first entry) and, per
    /// metric, when the board holds nothing of that metric yet. Ties do not break a record.
    public static func breaks(_ set: RecordSet, against board: [RecordMark]) -> [RecordBreak] {
        guard !board.isEmpty else { return [] }
        var result: [RecordBreak] = []
        for metric in RecordMetric.allCases {
            guard let value = value(metric, of: set) else { continue }
            let marks = board.filter { $0.metric == metric }
            guard !marks.isEmpty else { continue }
            if metric == .reps {
                let dominated = marks.contains { $0.weightKg >= set.weightKg && $0.value >= value }
                if dominated { continue }
                // Nothing at this weight or heavier to compare with: a new heavier weight, not a reps record.
                guard let beaten = marks.filter({ $0.weightKg >= set.weightKg }).map(\.value).max() else { continue }
                result.append(RecordBreak(metric: .reps, value: value, previousValue: beaten, isOutlier: false))
            } else {
                let best = marks.map(\.value).max() ?? 0
                guard value > best else { continue }
                let outlier = metric == .e1rm && value > best * outlierFactor
                result.append(RecordBreak(metric: metric, value: value, previousValue: best, isOutlier: outlier))
            }
        }
        return result.sorted { $0.metric.priority < $1.metric.priority }
    }

    /// Board after adding `set`: improved marks replace the old ones; reps marks the new one dominates drop out.
    public static func updated(_ board: [RecordMark], with set: RecordSet) -> [RecordMark] {
        var board = board
        for metric in RecordMetric.allCases {
            guard let value = value(metric, of: set) else { continue }
            let mark = RecordMark(metric: metric, value: value, setId: set.id, date: set.date, weightKg: set.weightKg)
            if metric == .reps {
                if board.contains(where: { $0.metric == .reps && $0.weightKg >= set.weightKg && $0.value >= value }) { continue }
                board.removeAll { $0.metric == .reps && $0.weightKg <= set.weightKg && $0.value <= value }
                board.append(mark)
            } else if let index = board.firstIndex(where: { $0.metric == metric }) {
                if value > board[index].value { board[index] = mark }
            } else {
                board.append(mark)
            }
        }
        return board
    }

    /// Replays the whole history in time order. Deterministic: the same sets always give the same board, which is
    /// what makes recomputing after an edit or delete consistent with live detection.
    public static func replay(_ sets: [RecordSet]) -> RecordReplay {
        var board: [RecordMark] = []
        var breaksBySet: [UUID: [RecordBreak]] = [:]
        for set in sets.sorted(by: { ($0.date, $0.order) < ($1.date, $1.order) }) {
            let hit = breaks(set, against: board)
            if !hit.isEmpty { breaksBySet[set.id] = hit }
            board = updated(board, with: set)
        }
        return RecordReplay(board: board, breaks: breaksBySet)
    }
}

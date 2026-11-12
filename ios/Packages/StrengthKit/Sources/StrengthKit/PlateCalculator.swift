import Foundation

/// Unit system of a plate set. The calculator itself is unit-agnostic: target, bar and plates just have to share one unit.
public enum PlateUnit: String, Sendable, CaseIterable {
    case kilograms, pounds
}

/// A plate denomination and how many PAIRS (one per side) the user owns.
public struct PlateStock: Equatable, Sendable {
    public let weight: Double
    public let pairs: Int

    public init(weight: Double, pairs: Int) {
        self.weight = weight
        self.pairs = pairs
    }
}

/// Bar kinds offered in the plate calculator.
public enum BarType: String, Sendable, CaseIterable {
    case olympic20, olympic15, ez, custom

    /// Weight of the bar in the given unit. `custom` has no fixed weight (the user types it).
    public func weight(in unit: PlateUnit) -> Double? {
        switch (self, unit) {
        case (.olympic20, .kilograms): 20
        case (.olympic20, .pounds): 45
        case (.olympic15, .kilograms): 15
        case (.olympic15, .pounds): 35
        case (.ez, .kilograms): 7.5
        case (.ez, .pounds): 20
        case (.custom, _): nil
        }
    }
}

/// Standard plate denominations per unit.
public enum PlateDefaults {
    public static func denominations(for unit: PlateUnit) -> [Double] {
        switch unit {
        case .kilograms: [25, 20, 15, 10, 5, 2.5, 1.25]
        case .pounds: [45, 35, 25, 10, 5, 2.5]
        }
    }

    /// Default stock: `pairs` pairs of each standard denomination.
    public static func stock(for unit: PlateUnit, pairs: Int = 4) -> [PlateStock] {
        denominations(for: unit).map { PlateStock(weight: $0, pairs: pairs) }
    }
}

/// One way to load the bar: plates for ONE side (heaviest first) and the resulting total.
public struct PlateLoad: Equatable, Sendable {
    public let platesPerSide: [Double]
    public let barWeight: Double

    public var perSideWeight: Double { platesPerSide.reduce(0, +) }
    public var total: Double { barWeight + 2 * perSideWeight }
}

public struct PlateSolution: Equatable, Sendable {
    public let target: Double
    /// The target is lighter than the empty bar.
    public let isBelowBar: Bool
    /// Best load at or below the target (the empty bar when the target is lighter than the bar).
    public let lower: PlateLoad
    /// Best load at or above the target; `nil` when the owned plates cannot reach it.
    public let upper: PlateLoad?

    public var isExact: Bool { !isBelowBar && abs(lower.total - target) < 0.005 }
    /// The exact load when there is one, else the closer of lower/upper (ties go down).
    public var best: PlateLoad {
        if isExact { return lower }
        guard let upper, !isBelowBar else { return lower }
        return (upper.total - target) < (target - lower.total) ? upper : lower
    }
}

/// Pure plate maths: which plates go on each side of the bar.
public enum PlateCalculator {
    /// Resolution of the subset search (1/100 of a unit), so floating point never decides a match.
    private static let scale = 100.0

    public static func solve(target: Double, bar: Double, stock: [PlateStock]) -> PlateSolution {
        let bar = max(0, bar.isFinite ? bar : 0)
        let emptyBar = PlateLoad(platesPerSide: [], barWeight: bar)
        guard target.isFinite else {
            return PlateSolution(target: 0, isBelowBar: true, lower: emptyBar, upper: nil)
        }
        let wanted = max(0, target - bar) / 2
        let wantedUnits = Int((wanted * scale).rounded())
        let plates = expand(stock)
        let reachable = Reachability(plates: plates, limit: wantedUnits + (plates.map(\.units).max() ?? 0))

        let belowBar = target < bar - 0.005
        let lowerUnits = belowBar ? 0 : (reachable.largest(atMost: wantedUnits) ?? 0)
        let upperUnits = belowBar && wantedUnits == 0 ? reachable.smallest(atLeast: 1) : reachable.smallest(atLeast: wantedUnits)
        let lower = PlateLoad(platesPerSide: reachable.plates(for: lowerUnits), barWeight: bar)
        let upper = upperUnits.map { PlateLoad(platesPerSide: reachable.plates(for: $0), barWeight: bar) }
        return PlateSolution(target: target, isBelowBar: belowBar, lower: lower, upper: upper)
    }

    // MARK: Search

    private struct Plate {
        let units: Int
        let weight: Double
    }

    /// One entry per physical plate on one side, heaviest first (so ties prefer heavier plates).
    private static func expand(_ stock: [PlateStock]) -> [Plate] {
        stock
            .filter { $0.weight.isFinite && $0.weight > 0 && $0.pairs > 0 }
            .sorted { $0.weight > $1.weight }
            .flatMap { entry in
                Array(repeating: Plate(units: Int((entry.weight * scale).rounded()), weight: entry.weight), count: min(entry.pairs, 12))
            }
            .filter { $0.units > 0 }
    }

    /// 0/1 subset search over single plates, minimizing plate count for every reachable sum.
    private struct Reachability {
        let plates: [Plate]
        let minCount: [Int]
        /// taken[i][s]: plate `i` is part of the best way to make sum `s` using plates `0...i`.
        let taken: [[Bool]]
        let limit: Int

        init(plates: [Plate], limit: Int) {
            self.plates = plates
            let total = plates.reduce(0) { $0 + $1.units }
            let cap = min(limit, total)
            self.limit = cap
            let unreachable = Int.max / 2
            var counts = [Int](repeating: unreachable, count: cap + 1)
            counts[0] = 0
            var choices: [[Bool]] = []
            for plate in plates {
                var row = [Bool](repeating: false, count: cap + 1)
                if plate.units <= cap {
                    for sum in stride(from: cap, through: plate.units, by: -1)
                    where counts[sum - plate.units] + 1 < counts[sum] {
                        counts[sum] = counts[sum - plate.units] + 1
                        row[sum] = true
                    }
                }
                choices.append(row)
            }
            minCount = counts
            taken = choices
        }

        private func isReachable(_ sum: Int) -> Bool { sum >= 0 && sum <= limit && minCount[sum] < Int.max / 2 }

        func largest(atMost value: Int) -> Int? {
            stride(from: min(value, limit), through: 0, by: -1).first(where: isReachable)
        }

        func smallest(atLeast value: Int) -> Int? {
            guard value <= limit else { return nil }
            return (value...limit).first(where: isReachable)
        }

        /// Plates (heaviest first) that make `sum`.
        func plates(for sum: Int) -> [Double] {
            var remaining = sum
            var result: [Double] = []
            for index in stride(from: plates.count - 1, through: 0, by: -1) where remaining > 0 && taken[index][remaining] {
                result.append(plates[index].weight)
                remaining -= plates[index].units
            }
            return result.sorted(by: >)
        }
    }
}

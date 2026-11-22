import DataKit
import Foundation

/// What the exercise screen plots: heaviest set, total volume or best estimated 1RM per session.
enum ProgressMetric: CaseIterable, Identifiable {
    case weight, volume, e1rm
    var id: Self { self }
}

/// How far back the chart reaches.
enum ProgressRange: CaseIterable, Identifiable {
    case month, quarter, all
    var id: Self { self }

    /// Days back from today; nil = everything.
    var days: Int? {
        switch self {
        case .month: 30
        case .quarter: 90
        case .all: nil
        }
    }
}

extension ExerciseHistoryModel {
    /// One point per session for the selected metric, oldest first, inside the selected range.
    var visiblePoints: [ChartPoint] {
        let unit = context.unit
        let all: [ChartPoint] = progress.points.compactMap { point in
            switch metric {
            case .weight: ChartPoint(date: point.date, value: unit.value(fromKilograms: point.bestWeightKg))
            case .volume: ChartPoint(date: point.date, value: unit.value(fromKilograms: point.volumeKg))
            case .e1rm: point.e1rmKg.map { ChartPoint(date: point.date, value: unit.value(fromKilograms: $0)) }
            }
        }
        return Self.window(all, days: range.days, now: now())
    }

    /// The points that lie within `days` of `now` (all of them when `days` is nil).
    static func window(_ points: [ChartPoint], days: Int?, now: Date, calendar: Calendar = .current) -> [ChartPoint] {
        guard let days, let from = calendar.date(byAdding: .day, value: -days, to: now) else { return points }
        return points.filter { $0.date >= from }
    }

    /// The newest value in the window.
    var currentValue: Double? { visiblePoints.last?.value }

    /// Newest minus oldest value in the window; nil with fewer than two points.
    var difference: Double? {
        let points = visiblePoints
        guard points.count >= 2, let first = points.first, let last = points.last else { return nil }
        return last.value - first.value
    }

    /// First and last date of the window, for the caption under the numbers.
    var windowDates: (from: Date, to: Date)? {
        let points = visiblePoints
        guard let first = points.first, let last = points.last else { return nil }
        return (first.date, last.date)
    }

    /// RiR of a set for display: the stored RiR, or what a half-step RPE implies. Nil when neither was recorded.
    static func rir(of input: SetInput) -> Double? {
        if let rpe = input.rpe { return max(0, 10 - rpe) }
        return input.rir.map(Double.init)
    }

    /// Logs a finished set on `date` and reloads, so the chart and the list move at once.
    func addSet(weightKg: Double, reps: Int, rir: Double?, tag: SetTag? = nil, on date: Date) async -> Bool {
        let input = SetInput.logged(weightKg: weightKg, reps: reps, rir: rir, tag: tag)
        do {
            try await context.editor.logSet(ref: ref, input: input, on: date)
        } catch {
            return false
        }
        await load()
        return true
    }
}

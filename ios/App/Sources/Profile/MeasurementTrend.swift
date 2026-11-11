import DataKit
import Foundation

/// One point of the weight chart, always in stored kilograms.
struct WeightPoint: Identifiable, Equatable {
    let id: UUID
    let date: Date
    let kilograms: Double
}

/// Pure helpers behind the weight chart and the "change" figure.
enum MeasurementTrend {
    /// Oldest first, as the chart wants them. Ties on the same day keep the order they were recorded in.
    static func points(from measurements: [MeasurementSnapshot]) -> [WeightPoint] {
        measurements
            .sorted { ($0.input.date, $0.createdAt) < ($1.input.date, $1.createdAt) }
            .map { WeightPoint(id: $0.id, date: $0.input.date, kilograms: $0.input.weightKg) }
    }

    /// Latest minus earliest, in kilograms; nil with fewer than two points.
    static func change(of points: [WeightPoint]) -> Double? {
        guard let first = points.first, let last = points.last, points.count >= 2 else { return nil }
        return last.kilograms - first.kilograms
    }
}

import DataKit
import Foundation

/// Pure rules for turning Health readings into new local measurements.
enum HealthImport {
    /// Two weights this close (kg) on the same day are the same weigh-in.
    static let duplicateToleranceKg = 0.05

    /// What is worth importing, oldest first (idempotent: running it again after saving the result yields nothing):
    /// - readings this app wrote itself are skipped (they exist locally already);
    /// - readings outside the accepted weight range are skipped;
    /// - one reading per day, the latest;
    /// - a day that already has a measurement with (nearly) the same weight is skipped.
    static func newMeasurements(
        from samples: [HealthWeightSample], existing: [MeasurementSnapshot], calendar: Calendar
    ) -> [MeasurementInput] {
        let candidates = samples.filter { !$0.isFromThisApp && OnboardingRules.isValidWeight(kg: $0.weightKg) }
        let latestPerDay = Dictionary(grouping: candidates) { calendar.startOfDay(for: $0.date) }
            .compactMap { $0.value.max { $0.date < $1.date } }
        return latestPerDay
            .filter { sample in !existing.contains { isDuplicate(sample, of: $0.input, calendar: calendar) } }
            .sorted { $0.date < $1.date }
            .map { MeasurementInput(date: $0.date, weightKg: $0.weightKg, source: .healthkit) }
    }

    private static func isDuplicate(
        _ sample: HealthWeightSample, of input: MeasurementInput, calendar: Calendar
    ) -> Bool {
        calendar.isDate(sample.date, inSameDayAs: input.date)
            && abs(sample.weightKg - input.weightKg) <= duplicateToleranceKg
    }

    /// Where to start reading: the day of the newest local measurement, or a year back when there is none.
    static func startDate(existing: [MeasurementSnapshot], now: Date, calendar: Calendar) -> Date {
        if let newest = existing.map(\.input.date).max() { return calendar.startOfDay(for: newest) }
        return calendar.date(byAdding: .year, value: -1, to: now) ?? now
    }
}

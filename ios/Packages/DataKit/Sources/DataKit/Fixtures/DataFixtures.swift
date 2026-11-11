import Foundation
import SwiftData

/// Sample data for previews and tests.
public enum DataFixtures {
    public static let userId = UUID(uuidString: "00000000-0000-4000-8000-000000000001")!

    public static func birthDate(yearsAgo: Int, from now: Date = Date()) -> Date {
        Calendar(identifier: .gregorian).date(byAdding: .year, value: -yearsAgo, to: now) ?? now
    }

    public static func profileInput(firstName: String = "Alex", yearsOld: Int = 28, now: Date = Date()) -> ProfileInput {
        ProfileInput(
            firstName: firstName, lastName: "Demir", birthDate: birthDate(yearsAgo: yearsOld, from: now),
            sex: .male, heightCm: 180, unitSystem: .metric, experience: .sixMonthsToTwoYears,
            goal: .strength, weeklyFrequency: 4, equipmentAccess: .fullGym, limitations: [], locale: "en"
        )
    }

    /// `count` weekly weigh-ins ending at `now`, newest last, trending slightly up.
    public static func measurementInputs(count: Int = 8, now: Date = Date()) -> [MeasurementInput] {
        let calendar = Calendar(identifier: .gregorian)
        return (0..<count).map { index in
            let date = calendar.date(byAdding: .day, value: -7 * (count - 1 - index), to: now) ?? now
            return MeasurementInput(date: date, weightKg: 80 + Double(index) * 0.3, bodyFatPct: index.isMultiple(of: 2) ? 15 : nil)
        }
    }

    /// Fills `container` with a profile, weight history, default settings and the required consents.
    @MainActor
    public static func seed(_ container: ModelContainer, userId: UUID = userId, now: Date = Date()) throws {
        let context = container.mainContext
        context.insert(UserProfile(userId: userId, input: profileInput(now: now), now: now))
        for input in measurementInputs(now: now) {
            context.insert(BodyMeasurement(userId: userId, input: input, now: now))
        }
        context.insert(UserSettings(userId: userId, now: now))
        for kind in [ConsentKind.terms, .privacy] {
            context.insert(ConsentRecord(userId: userId, kind: kind, version: "2026-11", granted: true, now: now))
        }
        try context.save()
    }
}

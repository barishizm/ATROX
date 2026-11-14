import Foundation

/// The anonymous monthly summary (docs/02-MIMARI.md §3.3). Nothing here identifies the user: bodies are banded or
/// rounded on the device, and `contributionKey` is a random key that is not linked to the account.
public struct ContributionPayload: Sendable, Equatable, Codable {
    public struct Lift: Sendable, Equatable, Codable {
        public var exerciseId: String
        public var bestE1rmKg: Double
        public var bestSetReps: Int
        public var sessionsInMonth: Int

        public init(exerciseId: String, bestE1rmKg: Double, bestSetReps: Int, sessionsInMonth: Int) {
            self.exerciseId = exerciseId
            self.bestE1rmKg = bestE1rmKg
            self.bestSetReps = bestSetReps
            self.sessionsInMonth = sessionsInMonth
        }

        enum CodingKeys: String, CodingKey {
            case exerciseId = "exercise_id", bestE1rmKg = "best_e1rm_kg", bestSetReps = "best_set_reps", sessionsInMonth = "sessions_in_month"
        }
    }

    public var contributionKey: UUID
    public var sex: String
    public var ageBand: Int
    public var bodyweightKg: Int
    public var heightBand: Int
    public var experienceBand: String
    public var frequencyBand: String
    /// `YYYY-MM`, the month the lifts come from.
    public var month: String
    public var modelVersion: String
    public var lifts: [Lift]

    public init(
        contributionKey: UUID, sex: String, ageBand: Int, bodyweightKg: Int, heightBand: Int, experienceBand: String,
        frequencyBand: String, month: String, modelVersion: String, lifts: [Lift]
    ) {
        self.contributionKey = contributionKey
        self.sex = sex
        self.ageBand = ageBand
        self.bodyweightKg = bodyweightKg
        self.heightBand = heightBand
        self.experienceBand = experienceBand
        self.frequencyBand = frequencyBand
        self.month = month
        self.modelVersion = modelVersion
        self.lifts = lifts
    }

    enum CodingKeys: String, CodingKey {
        case contributionKey = "contribution_key", sex, ageBand = "age_band", bodyweightKg = "bodyweight_kg"
        case heightBand = "height_band", experienceBand = "experience_band", frequencyBand = "frequency_band"
        case month, modelVersion = "model_version", lifts
    }

    /// Human-readable JSON, shown on the transparency screen exactly as it is (or would be) sent.
    public func readableJSON() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return (try? encoder.encode(self)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }
}

/// Everything the summary is built from, already read from the store.
public struct ContributionInputs: Sendable {
    public var sex: Sex
    public var birthDate: Date
    public var heightCm: Double
    public var bodyweightKg: Double
    public var experience: Experience
    public var weeklyFrequency: Int

    public init(sex: Sex, birthDate: Date, heightCm: Double, bodyweightKg: Double, experience: Experience, weeklyFrequency: Int) {
        self.sex = sex
        self.birthDate = birthDate
        self.heightCm = heightCm
        self.bodyweightKg = bodyweightKg
        self.experience = experience
        self.weeklyFrequency = weeklyFrequency
    }
}

/// Banding and rounding done on the device, before anything leaves it.
public enum ContributionBanding {
    /// Lower edge of the 5-year band, within what the server accepts.
    public static func ageBand(_ age: Int) -> Int { min(95, max(10, age / 5 * 5)) }

    /// Lower edge of the 5 cm band.
    public static func heightBand(_ cm: Double) -> Int { min(230, max(120, Int(cm / 5) * 5)) }

    public static func bodyweight(_ kg: Double) -> Int { min(300, max(30, Int(kg.rounded()))) }

    public static func frequencyBand(_ perWeek: Int) -> String {
        switch perWeek {
        case ..<3: "1-2"
        case 3...4: "3-4"
        case 5...6: "5-6"
        default: "7+"
        }
    }

    /// `YYYY-MM` of the month containing `date`, in the calendar's time zone.
    public static func monthString(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", parts.year ?? 0, parts.month ?? 0)
    }
}

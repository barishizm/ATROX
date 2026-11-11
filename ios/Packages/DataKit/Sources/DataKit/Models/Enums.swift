import Foundation

// Raw values match the CHECK constraints in supabase/migrations (docs/02-MIMARI.md §2.3, §3.1).

public enum Sex: String, Sendable, Codable, CaseIterable {
    case male, female, unspecified
}

public enum UnitSystem: String, Sendable, Codable, CaseIterable {
    case metric, imperial
}

public enum Experience: String, Sendable, Codable, CaseIterable {
    case noExperience = "none"
    case under6Months = "under_6_months"
    case sixMonthsToTwoYears = "six_months_to_2_years"
    case twoToFiveYears = "two_to_5_years"
    case over5Years = "over_5_years"
}

public enum Goal: String, Sendable, Codable, CaseIterable {
    case strength
    case muscleGain = "muscle_gain"
    case fatLoss = "fat_loss"
    case generalHealth = "general_health"
}

public enum EquipmentAccess: String, Sendable, Codable, CaseIterable {
    case fullGym = "full_gym"
    case homeBarbell = "home_barbell"
    case homeDumbbell = "home_dumbbell"
    case bodyweightOnly = "bodyweight_only"
}

public enum MeasurementSource: String, Sendable, Codable, CaseIterable {
    case manual, healthkit
    case imported = "import"
}

public enum ConsentKind: String, Sendable, Codable, CaseIterable {
    case terms, privacy
    case aiSharing = "ai_sharing"
    case mlContribution = "ml_contribution"
}

public enum ThemePreference: String, Sendable, Codable, CaseIterable {
    case system, dark, light
}

public enum WeightUnit: String, Sendable, Codable, CaseIterable {
    case kg, lb
}

public enum LengthUnit: String, Sendable, Codable, CaseIterable {
    case cm
    case inch = "in"
}

public enum ReferenceGroup: String, Sendable, Codable, CaseIterable {
    case gym, general
}

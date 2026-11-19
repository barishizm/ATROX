import Foundation

public enum MealType: String, Sendable, Codable, CaseIterable {
    case breakfast, lunch, dinner, snack

    /// The meal a food eaten at `date` most likely belongs to (used to pre-select the picker).
    public static func suggested(for date: Date, calendar: Calendar = .current) -> MealType {
        switch calendar.component(.hour, from: date) {
        case 4..<11: .breakfast
        case 11..<16: .lunch
        case 16..<22: .dinner
        default: .snack
        }
    }
}

public enum FoodSource: String, Sendable, Codable, CaseIterable {
    case photo, text, barcode, manual
}

public enum TargetMode: String, Sendable, Codable, CaseIterable {
    /// Calculated from the profile (goal, weight, training frequency).
    case auto
    /// Typed in by the user.
    case manual
}

public enum ActivityLevel: String, Sendable, Codable, CaseIterable {
    case sedentary, light, moderate, active
    case veryActive = "very_active"

    /// Multiplier on basal metabolic rate (standard Harris-Benedict factors).
    public var factor: Double {
        switch self {
        case .sedentary: 1.2
        case .light: 1.375
        case .moderate: 1.55
        case .active: 1.725
        case .veryActive: 1.9
        }
    }

    /// Activity implied by how many days a week the user trains.
    public static func from(weeklyFrequency days: Int) -> ActivityLevel {
        switch days {
        case ..<2: .sedentary
        case 2: .light
        case 3...4: .moderate
        case 5...6: .active
        default: .veryActive
        }
    }
}

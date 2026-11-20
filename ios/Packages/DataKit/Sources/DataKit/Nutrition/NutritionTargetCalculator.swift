import Foundation

/// A daily calorie and macro target.
public struct NutritionTargetValues: Sendable, Equatable {
    public var calories: Int
    public var proteinG: Int
    public var carbsG: Int
    public var fatG: Int

    public init(calories: Int, proteinG: Int, carbsG: Int, fatG: Int) {
        self.calories = calories
        self.proteinG = proteinG
        self.carbsG = carbsG
        self.fatG = fatG
    }
}

/// How hard the calorie adjustment of a fat-loss or gain goal is pushed.
public enum NutritionPace: String, Sendable, CaseIterable {
    case gentle, steady, fast
}

/// Derives the automatic target from the profile (docs/superpowers/specs/2026-11-19-food-calorie-tracking-design.md).
/// Mifflin-St Jeor basal rate × activity factor × goal adjustment; protein per kg, fat 25 % of calories, the rest carbs.
/// Safety: never below 1500 kcal (men) / 1200 kcal (everyone else), and under 18 no deficit.
public enum NutritionTargetCalculator {
    public struct Input: Sendable, Equatable {
        public var sex: Sex
        public var ageYears: Int
        public var heightCm: Double
        public var weightKg: Double
        public var goal: Goal
        public var activity: ActivityLevel
        public var pace: NutritionPace

        public init(
            sex: Sex, ageYears: Int, heightCm: Double, weightKg: Double, goal: Goal, activity: ActivityLevel, pace: NutritionPace = .steady
        ) {
            self.sex = sex
            self.ageYears = ageYears
            self.heightCm = heightCm
            self.weightKg = weightKg
            self.goal = goal
            self.activity = activity
            self.pace = pace
        }
    }

    public static func basalRate(_ input: Input) -> Double {
        let base = 10 * input.weightKg + 6.25 * input.heightCm - 5 * Double(input.ageYears)
        switch input.sex {
        case .male: return base + 5
        case .female: return base - 161
        case .unspecified: return base - 78 // midpoint of the two
        }
    }

    public static func goalMultiplier(_ goal: Goal, pace: NutritionPace = .steady) -> Double {
        switch (goal, pace) {
        case (.strength, _): 1.05
        case (.muscleGain, .gentle): 1.05
        case (.muscleGain, .steady): 1.10
        case (.muscleGain, .fast): 1.15
        case (.fatLoss, .gentle): 0.90
        case (.fatLoss, .steady): 0.85
        case (.fatLoss, .fast): 0.80
        case (.generalHealth, _): 1.0
        }
    }

    public static func minimumCalories(for sex: Sex) -> Int { sex == .male ? 1500 : 1200 }

    public static func target(for input: Input) -> NutritionTargetValues {
        var multiplier = goalMultiplier(input.goal, pace: input.pace)
        if input.ageYears < 18 { multiplier = max(multiplier, 1.0) }
        let maintenance = basalRate(input) * input.activity.factor
        let raw = Int((maintenance * multiplier / 10).rounded()) * 10
        let calories = max(raw, minimumCalories(for: input.sex))

        let proteinPerKg = input.goal == .fatLoss ? 2.0 : 1.8
        var protein = Int((input.weightKg * proteinPerKg).rounded())
        // Protein may not take more than 40 % of a small budget.
        protein = min(protein, Int(Double(calories) * 0.4 / 4))
        let fat = Int((Double(calories) * 0.25 / 9).rounded())
        let carbs = max(0, Int((Double(calories - protein * 4 - fat * 9) / 4).rounded()))
        return NutritionTargetValues(calories: calories, proteinG: protein, carbsG: carbs, fatG: fat)
    }
}

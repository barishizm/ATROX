import DataKit
import Foundation
import Observation

enum QuizStep: Hashable {
    case goal, weight, goalWeight, pace, activity, cooking, time, diet, plan
}

enum CookingSkill: String, Codable, CaseIterable { case beginner, comfortable, expert }
enum CookingTime: String, Codable, CaseIterable { case quick, medium, relaxed }
enum DietStyle: String, Codable, CaseIterable { case anything, vegetarian, vegan }

/// Kitchen answers of the first-run quiz, kept on the device for the recipes page.
struct NutritionPreferences: Codable, Equatable {
    var cooking: CookingSkill
    var time: CookingTime
    var diet: DietStyle

    private static func key(_ userId: UUID) -> String { "nutrition.preferences.\(userId.uuidString)" }
    private static func doneKey(_ userId: UUID) -> String { "nutrition.quiz.done.\(userId.uuidString)" }

    /// Whether the quiz was answered or skipped; it opens by itself only once.
    static func quizFinished(userId: UUID) -> Bool { UserDefaults.standard.bool(forKey: doneKey(userId)) }
    static func markQuizFinished(userId: UUID) { UserDefaults.standard.set(true, forKey: doneKey(userId)) }

    static func load(userId: UUID) -> NutritionPreferences? {
        UserDefaults.standard.data(forKey: key(userId)).flatMap { try? JSONDecoder().decode(Self.self, from: $0) }
    }

    func save(userId: UUID) {
        if let data = try? JSONEncoder().encode(self) { UserDefaults.standard.set(data, forKey: Self.key(userId)) }
    }
}

/// The first-run quiz: up to nine short questions, then a daily plan the user can still edit.
@MainActor
@Observable
final class NutritionOnboardingModel {
    let profile: NutritionProfile
    let unit: WeightUnit
    var goal: Goal
    /// Weights are typed in the user's unit.
    var weight: Double
    var goalWeight: Double = 0
    var pace: NutritionPace = .steady
    var activity: ActivityLevel
    var cooking: CookingSkill = .comfortable
    var time: CookingTime = .medium
    var diet: DietStyle = .anything
    var calories: Double = 0
    var protein: Double = 0
    var carbs: Double = 0
    var fat: Double = 0
    private(set) var index = 0
    private(set) var saving = false
    private(set) var failed = false

    init(profile: NutritionProfile, preferences: NutritionPreferences?) {
        self.profile = profile
        unit = profile.weightUnit
        goal = profile.goal
        weight = profile.weightKg.map { (profile.weightUnit.value(fromKilograms: $0) * 10).rounded() / 10 } ?? 0
        activity = profile.activity == .veryActive ? .active : profile.activity
        if let preferences {
            cooking = preferences.cooking
            time = preferences.time
            diet = preferences.diet
        }
    }

    var wantsChange: Bool { goal == .fatLoss || goal == .muscleGain }

    var steps: [QuizStep] {
        var list: [QuizStep] = [.goal, .weight]
        if wantsChange { list += [.goalWeight, .pace] }
        return list + [.activity, .cooking, .time, .diet, .plan]
    }

    var step: QuizStep { steps[min(index, steps.count - 1)] }
    var isLast: Bool { step == .plan }
    var progress: Double { Double(index + 1) / Double(steps.count) }

    var canContinue: Bool {
        switch step {
        case .weight, .goalWeight: (step == .weight ? weight : goalWeight) > 0
        case .plan: calories >= 800
        default: true
        }
    }

    var weightKg: Double { unit.kilograms(from: weight) }

    /// The calculated plan for the answers so far.
    var suggestion: NutritionTargetValues {
        NutritionTargetCalculator.target(for: .init(
            sex: profile.sex, ageYears: profile.ageYears, heightCm: profile.heightCm, weightKg: weightKg, goal: goal, activity: activity,
            pace: wantsChange ? pace : .steady
        ))
    }

    func next() {
        guard index < steps.count - 1 else { return }
        index += 1
        if step == .goalWeight, goalWeight == 0 { goalWeight = (weight * (goal == .fatLoss ? 0.9 : 1.05) * 10).rounded() / 10 }
        if step == .plan { applySuggestion() }
    }

    func back() { index = max(0, index - 1) }

    /// Answers a choice question and moves on.
    func choose(_ apply: () -> Void) {
        apply()
        next()
    }

    func applySuggestion() {
        let values = suggestion
        calories = Double(values.calories)
        protein = Double(values.proteinG)
        carbs = Double(values.carbsG)
        fat = Double(values.fatG)
    }

    var edited: NutritionTargetValues {
        NutritionTargetValues(calories: Int(calories), proteinG: Int(protein), carbsG: Int(carbs), fatG: Int(fat))
    }

    /// Saves the plan, the weigh-in, the goal weight and the kitchen answers.
    func finish(on model: NutritionModel) async -> Bool {
        saving = true
        failed = false
        defer { saving = false }
        let input = NutritionTargetInput(mode: edited == suggestion ? .auto : .manual, values: edited, activity: activity)
        guard await model.setTarget(input) else {
            failed = true
            return false
        }
        if abs(weightKg - (profile.weightKg ?? 0)) > 0.05 { _ = await model.logWeight(kg: weightKg) }
        if wantsChange, goalWeight > 0 { _ = await model.setGoalWeight(kg: unit.kilograms(from: goalWeight)) }
        NutritionPreferences(cooking: cooking, time: time, diet: diet).save(userId: model.userId)
        NutritionPreferences.markQuizFinished(userId: model.userId)
        await model.load()
        return true
    }
}

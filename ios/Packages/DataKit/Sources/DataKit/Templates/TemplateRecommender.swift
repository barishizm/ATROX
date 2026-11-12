import Foundation

/// What the recommender reads from the user's profile.
public struct TemplateProfile: Sendable, Equatable {
    public var experience: Experience
    public var goal: Goal
    public var weeklyFrequency: Int
    public var equipment: EquipmentAccess

    public init(experience: Experience, goal: Goal, weeklyFrequency: Int, equipment: EquipmentAccess) {
        self.experience = experience
        self.goal = goal
        self.weeklyFrequency = weeklyFrequency
        self.equipment = equipment
    }

    public init(_ input: ProfileInput) {
        self.init(
            experience: input.experience, goal: input.goal, weeklyFrequency: input.weeklyFrequency,
            equipment: input.equipmentAccess)
    }
}

public struct TemplateRecommendation: Sendable, Equatable, Identifiable {
    public let template: ProgramTemplate
    public let score: Double
    public var id: String { template.id }
}

/// Picks the templates that fit a profile best (P034): training days first, then equipment, experience and goal.
public enum TemplateRecommender {
    public static func recommend(
        _ templates: [ProgramTemplate], for profile: TemplateProfile, count: Int = 2
    ) -> [TemplateRecommendation] {
        let scored = templates.enumerated().map { index, template in
            (index, TemplateRecommendation(template: template, score: score(template, for: profile)))
        }
        return scored
            .sorted { $0.1.score != $1.1.score ? $0.1.score > $1.1.score : $0.0 < $1.0 }
            .prefix(count).map(\.1)
    }

    static func score(_ template: ProgramTemplate, for profile: TemplateProfile) -> Double {
        var score = 0.0
        // Training days: an exact match is worth the most, each day off costs.
        let daysOff = abs(template.daysPerWeek - profile.weeklyFrequency)
        score += daysOff == 0 ? 4 : -Double(daysOff) * 1.5
        // Equipment: a template that needs more than the user has is a poor fit; a plainer one is fine but not ideal.
        let gap = EquipmentRules.rank(template.equipment) - EquipmentRules.rank(profile.equipment)
        score += gap > 0 ? -Double(gap) * 4 : -Double(-gap) * 0.75
        score -= Double(TemplateLevel.distance(from: profile.experience, to: template.level)) * 2
        if template.goals.contains(profile.goal) { score += 1.5 }
        // The first goal listed is what the template is mainly for.
        if template.goals.first == profile.goal { score += 1 }
        return score
    }
}

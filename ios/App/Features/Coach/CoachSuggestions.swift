import DesignSystem
import Foundation

/// The four starter questions of an empty conversation (P080): rule-based, from the user's own data, no model call.
enum CoachSuggestions {
    struct Facts: Equatable {
        var weakestMuscle: String?
        var hasWorkouts = false
        var hasRoutine = false
    }

    static func make(_ facts: Facts, locale: Locale) -> [String] {
        func text(_ key: String, _ args: CVarArg...) -> String { LocalizedText.string(key, locale: locale, arguments: args) }
        var result: [String] = []
        result.append(facts.hasRoutine ? text("coach.suggest.review.program") : text("coach.suggest.make.program"))
        if let muscle = facts.weakestMuscle, let name = Muscle(rawValue: muscle)?.localizedName(locale: locale) {
            result.append(text("coach.suggest.weakest %@", name))
        }
        result.append(facts.hasWorkouts ? text("coach.suggest.recent") : text("coach.suggest.start"))
        for fallback in ["coach.suggest.score", "coach.suggest.recovery", "coach.suggest.progress"] where result.count < 4 {
            result.append(text(fallback))
        }
        return Array(result.prefix(4))
    }
}

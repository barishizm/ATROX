import Foundation

/// What the personalizer needs to know about one catalog exercise.
public struct TemplateExerciseInfo: Sendable, Equatable, Identifiable {
    public let id: String
    public let nameEn: String
    public let nameTr: String
    public let equipment: String?
    public let movementPattern: String
    public let primaryMuscles: [String]
    public let level: String
    public let category: String

    public init(
        id: String, nameEn: String, nameTr: String, equipment: String?, movementPattern: String,
        primaryMuscles: [String], level: String = "beginner", category: String = "strength"
    ) {
        self.id = id
        self.nameEn = nameEn
        self.nameTr = nameTr
        self.equipment = equipment
        self.movementPattern = movementPattern
        self.primaryMuscles = primaryMuscles
        self.level = level
        self.category = category
    }

    public init(_ record: CatalogRecord) {
        self.init(
            id: record.id, nameEn: record.translations["en"]?.name ?? record.id,
            nameTr: record.translations["tr"]?.name ?? record.translations["en"]?.name ?? record.id,
            equipment: record.equipment, movementPattern: record.movementPattern,
            primaryMuscles: record.primaryMuscles, level: record.level, category: record.category)
    }

    public init(_ exercise: Exercise) {
        self.init(
            id: exercise.id, nameEn: exercise.nameEn, nameTr: exercise.nameTr, equipment: exercise.equipment,
            movementPattern: exercise.movementPattern, primaryMuscles: exercise.primaryMuscles,
            level: exercise.level, category: exercise.category)
    }

    public func name(languageCode: String) -> String { languageCode == "tr" ? nameTr : nameEn }
}

/// Which equipment each access level has (P034). A catalog exercise with no equipment is bodyweight.
public enum EquipmentRules {
    public static func allows(_ access: EquipmentAccess, equipment: String?) -> Bool {
        guard let equipment else { return true }
        switch access {
        case .fullGym: return true
        case .homeBarbell: return ["body_only", "barbell", "ez_bar", "dumbbell", "bands"].contains(equipment)
        case .homeDumbbell: return ["body_only", "dumbbell", "bands"].contains(equipment)
        case .bodyweightOnly: return equipment == "body_only"
        }
    }

    /// Fuller access = bigger number.
    public static func rank(_ access: EquipmentAccess) -> Int {
        switch access {
        case .fullGym: 3
        case .homeBarbell: 2
        case .homeDumbbell: 1
        case .bodyweightOnly: 0
        }
    }
}

/// Which body areas an exercise loads enough to be worth flagging (P034). Deliberately coarse: it flags by movement
/// pattern and a few name patterns, and the answer is only ever "consider the alternative", never "do not train".
public enum LimitationRules {
    public static func areas(for exercise: TemplateExerciseInfo) -> Set<BodyLimitation> {
        let id = exercise.id, pattern = exercise.movementPattern
        var areas = Set<BodyLimitation>()
        if pattern == "vertical_push" || id.contains("dip") || id.contains("upright-row") || id.contains("military") {
            areas.insert(.shoulder)
        }
        if pattern == "hip_hinge" || id.contains("deadlift") || id.contains("good-morning") || id.contains("bent-over") {
            areas.insert(.lowerBack)
        }
        if pattern == "squat" || id.contains("lunge") || id.contains("step-up") || id.contains("jump") {
            areas.insert(.knee)
        }
        if pattern == "isolation_triceps" || id.contains("dip") || id.contains("skull") { areas.insert(.elbow) }
        let wristNames = ["push-up", "pushup", "wrist-curl", "barbell-curl"]
        if wristNames.contains(where: id.contains) {
            areas.insert(.wrist)
        }
        if pattern == "hip_hinge" || id.contains("lunge") || id.contains("sumo") || id.contains("split-squat") {
            areas.insert(.hip)
        }
        return areas
    }
}

public struct PersonalizedExercise: Sendable, Equatable {
    /// The targets of the template row (sets, reps, RIR, rest).
    public let target: ProgramTemplate.Exercise
    /// The exercise to use: the template's, or its replacement when the user's equipment does not fit.
    public let exerciseId: String
    /// The template's own exercise when it was replaced for the equipment.
    public let replacedId: String?
    /// The user's limited body areas this exercise loads.
    public let flaggedAreas: [BodyLimitation]
    /// A same-pattern exercise that avoids those areas, when one exists.
    public let alternativeId: String?
    /// Nothing the user's equipment allows does the same job; the template's exercise stays.
    public let isUnavailable: Bool

    public var isFlagged: Bool { !flaggedAreas.isEmpty }
}

public struct PersonalizedDay: Sendable, Equatable {
    public let name: TemplateText
    public let exercises: [PersonalizedExercise]
}

public struct PersonalizedTemplate: Sendable, Equatable {
    public let template: ProgramTemplate
    public let days: [PersonalizedDay]

    public var replacedCount: Int { days.flatMap(\.exercises).filter { $0.replacedId != nil }.count }
    public var flaggedCount: Int { days.flatMap(\.exercises).filter(\.isFlagged).count }
    public var unavailableCount: Int { days.flatMap(\.exercises).filter(\.isUnavailable).count }
}

/// Adapts a template to the user's equipment and limitations (P034): an exercise the equipment does not allow is
/// replaced by one with the same movement pattern and muscle; exercises that load a limited area get an alternative.
public struct TemplatePersonalizer: Sendable {
    private let catalog: [String: TemplateExerciseInfo]
    private let ordered: [TemplateExerciseInfo]

    public init(catalog: [TemplateExerciseInfo]) {
        self.ordered = catalog.sorted { $0.id < $1.id }
        self.catalog = Dictionary(ordered.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    public func info(for id: String) -> TemplateExerciseInfo? { catalog[id] }

    public func personalize(
        _ template: ProgramTemplate, equipment: EquipmentAccess, limitations: [BodyLimitation] = []
    ) -> PersonalizedTemplate {
        let days = template.days.map { day -> PersonalizedDay in
            var used = Set(day.exercises.map(\.id))
            let rows = day.exercises.map { row -> PersonalizedExercise in
                var chosen = row.id
                var replaced: String?
                var unavailable = false
                if let original = catalog[row.id] {
                    if !EquipmentRules.allows(equipment, equipment: original.equipment) {
                        if let swap = substitute(for: original, equipment: equipment, avoiding: [], excluding: used) {
                            chosen = swap.id
                            replaced = row.id
                            used.insert(swap.id)
                        } else {
                            unavailable = true
                        }
                    }
                } else {
                    unavailable = true
                }
                let flagged = catalog[chosen].map { LimitationRules.areas(for: $0).intersection(limitations) } ?? []
                var alternative: String?
                if !flagged.isEmpty, let current = catalog[chosen] {
                    alternative = substitute(for: current, equipment: equipment, avoiding: flagged, excluding: used)?.id
                }
                return PersonalizedExercise(
                    target: row, exerciseId: chosen, replacedId: replaced,
                    flaggedAreas: BodyLimitation.allCases.filter(flagged.contains), alternativeId: alternative,
                    isUnavailable: unavailable)
            }
            return PersonalizedDay(name: day.name, exercises: rows)
        }
        return PersonalizedTemplate(template: template, days: days)
    }

    /// The best stand-in for `original`: allowed by the equipment, same movement pattern, same main muscle, no harder
    /// than the original, as close in equipment as possible, and loading none of the `avoiding` areas. When the whole
    /// pattern loads an avoided area (every overhead press loads the shoulder), a related pattern may stand in.
    func substitute(
        for original: TemplateExerciseInfo, equipment: EquipmentAccess, avoiding: Set<BodyLimitation>,
        excluding: Set<String>
    ) -> TemplateExerciseInfo? {
        func pool(pattern: String) -> [TemplateExerciseInfo] {
            ordered.filter { candidate in
                candidate.id != original.id && !excluding.contains(candidate.id)
                    && ["strength", "powerlifting"].contains(candidate.category) && candidate.level != "expert"
                    && candidate.movementPattern == pattern
                    && EquipmentRules.allows(equipment, equipment: candidate.equipment)
                    && LimitationRules.areas(for: candidate).isDisjoint(with: avoiding)
            }
        }
        func best(_ candidates: [TemplateExerciseInfo]) -> TemplateExerciseInfo? {
            candidates.min { lhs, rhs in
                let left = (levelRank(lhs.level) > levelRank(original.level) ? 1 : 0, affinity(lhs, to: original), lhs.id)
                let right = (levelRank(rhs.level) > levelRank(original.level) ? 1 : 0, affinity(rhs, to: original), rhs.id)
                return left < right
            }
        }
        let same = pool(pattern: original.movementPattern)
        let sameMuscle = same.filter { $0.primaryMuscles.first == original.primaryMuscles.first }
        let candidates = sameMuscle.isEmpty
            ? same.filter { !Set($0.primaryMuscles).isDisjoint(with: original.primaryMuscles) } : sameMuscle
        if let found = best(candidates) { return found }
        guard !avoiding.isEmpty else { return nil }
        for pattern in Self.relatedPatterns[original.movementPattern] ?? [] {
            if let found = best(pool(pattern: pattern)) { return found }
        }
        return nil
    }

    /// Where to look when an alternative to a limited movement pattern has to come from elsewhere.
    private static let relatedPatterns: [String: [String]] = [
        "vertical_push": ["horizontal_push"],
        "hip_hinge": ["isolation_hamstrings", "squat"],
        "squat": ["hip_hinge", "isolation_hamstrings"],
        "isolation_triceps": ["isolation_biceps"]
    ]

    private func levelRank(_ level: String) -> Int {
        switch level {
        case "beginner": 0
        case "intermediate": 1
        default: 2
        }
    }

    /// 0 = same equipment, then dumbbells, bodyweight, machines/cables, anything else.
    private func affinity(_ candidate: TemplateExerciseInfo, to original: TemplateExerciseInfo) -> Int {
        if candidate.equipment == original.equipment { return 0 }
        switch candidate.equipment {
        case "dumbbell": return 1
        case nil, "body_only": return 2
        case "machine", "cable": return 3
        default: return 4
        }
    }
}

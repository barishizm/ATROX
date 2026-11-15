import DataKit
import Foundation
import Observation

/// Program templates (P034): the recommended two for the user's profile, the full list, the personalized preview of
/// one template and creating an editable copy of it.
@MainActor
@Observable
final class TemplateListModel {
    let userId: UUID
    let plan: RoutinePlanStore
    let templates: [ProgramTemplate]
    /// The templates that fit the profile best; empty when there is no profile yet.
    private(set) var recommended: [ProgramTemplate] = []
    let equipment: EquipmentAccess
    let limitations: [BodyLimitation]
    private(set) var isInstalling = false
    var errorOccurred = false

    private let personalizer: TemplatePersonalizer
    private let repository: any RoutineRepository

    init(
        userId: UUID, templates: [ProgramTemplate], catalog: [TemplateExerciseInfo], profile: ProfileInput?,
        repository: any RoutineRepository, plan: RoutinePlanStore
    ) {
        self.userId = userId
        self.templates = templates
        self.personalizer = TemplatePersonalizer(catalog: catalog)
        self.repository = repository
        self.plan = plan
        equipment = profile?.equipmentAccess ?? .fullGym
        limitations = LimitationCodec.decode(profile?.limitations ?? []).areas
        if let profile {
            recommended = TemplateRecommender.recommend(templates, for: TemplateProfile(profile)).map(\.template)
        }
    }

    var others: [ProgramTemplate] {
        let ids = Set(recommended.map(\.id))
        return templates.filter { !ids.contains($0.id) }
    }

    func template(id: String) -> ProgramTemplate? { templates.first { $0.id == id } }

    func personalized(_ template: ProgramTemplate) -> PersonalizedTemplate {
        personalizer.personalize(template, equipment: equipment, limitations: limitations)
    }

    func exerciseName(_ id: String, languageCode: String) -> String {
        personalizer.info(for: id)?.name(languageCode: languageCode) ?? id
    }

    /// Creates the programs of a template and returns their names. Every training day becomes its own program
    /// ("Push", "Pull", "Legs"), so nobody has to carry three days in one place; `weekdayLabels` (one per day, in
    /// order) are appended to the names. The first program the user owns becomes the active one.
    func use(
        _ template: ProgramTemplate, languageCode: String, useAlternatives: Bool, weekdayLabels: [String] = [],
        weekdays: [Int] = []
    ) async -> [String]? {
        guard !isInstalling else { return nil }
        isInstalling = true
        defer { isInstalling = false }
        func label(_ name: String, _ index: Int) -> String {
            index < weekdayLabels.count ? "\(name) · \(weekdayLabels[index])" : name
        }
        do {
            let hadPrograms = try await !repository.all(userId: userId).isEmpty
            let installed = try await repository.install(
                personalized(template), languageCode: languageCode, useAlternatives: useAlternatives, userId: userId)
            let full = try await repository.routine(id: installed.id) ?? installed
            var ids = [full.id]
            var names = [label(full.name, 0)]
            if full.days.count > 1 {
                // Copy first, trim afterwards: trimming the original early would leave the copies without days.
                for day in full.days.dropFirst() {
                    ids.append(try await repository.duplicate(routineId: full.id, name: day.name).id)
                }
                names = []
                for (index, day) in full.days.enumerated() {
                    guard let target = try await repository.routine(id: ids[index]) else { continue }
                    for (position, other) in target.days.enumerated() where position != index {
                        try await repository.deleteDay(id: other.id)
                    }
                    let name = label(day.name, index)
                    try await repository.update(id: ids[index], name: name, notes: full.notes)
                    names.append(name)
                    if index < weekdays.count, let kept = try await repository.routine(id: ids[index])?.days.first {
                        plan.assign(dayId: kept.id, toWeekday: weekdays[index])
                    }
                }
            } else if !weekdayLabels.isEmpty {
                try await repository.update(id: full.id, name: names[0], notes: full.notes)
            }
            if full.days.count == 1, let first = weekdays.first, let day = full.days.first {
                plan.assign(dayId: day.id, toWeekday: first)
            }
            if !hadPrograms { plan.setActive(ids[0]) }
            return names
        } catch {
            errorOccurred = true
            return nil
        }
    }
}

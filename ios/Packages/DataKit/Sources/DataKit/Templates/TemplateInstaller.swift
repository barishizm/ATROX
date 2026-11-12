import Foundation

public extension RoutineRepository {
    /// Creates an editable routine from a personalized template (P034): the template itself stays untouched.
    /// With `useAlternatives` a flagged exercise is swapped for its safer alternative where one exists.
    @discardableResult
    func install(
        _ personalized: PersonalizedTemplate, name: String? = nil, languageCode: String, useAlternatives: Bool,
        userId: UUID
    ) async throws -> RoutineSnapshot {
        let template = personalized.template
        let routine = try await create(
            name: name ?? template.name.resolve(languageCode: languageCode),
            notes: template.summary.resolve(languageCode: languageCode), userId: userId)
        for day in personalized.days {
            let created = try await addDay(routineId: routine.id, name: day.name.resolve(languageCode: languageCode))
            for row in day.exercises {
                let id = useAlternatives ? (row.alternativeId ?? row.exerciseId) : row.exerciseId
                let target = row.target
                try await addExercise(
                    dayId: created.id, ref: .catalog(id),
                    input: RoutineExerciseInput(
                        targetSets: target.sets, targetRepsMin: target.repsMin, targetRepsMax: target.repsMax,
                        targetRir: target.rir, restSeconds: target.restSeconds))
            }
        }
        return try await self.routine(id: routine.id) ?? routine
    }
}

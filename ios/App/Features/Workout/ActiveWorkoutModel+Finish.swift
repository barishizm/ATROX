import DataKit
import Foundation

/// What to ask the user when they tap Finish (P041).
enum FinishPrompt: Equatable {
    /// Everything is done: the usual "finish workout?".
    case confirm
    /// Some sets were never completed: "Delete and finish" / "Go back".
    case openSets(Int)
    /// Shorter than two minutes: save it? (`open` sets would be deleted.)
    case short(open: Int)
    /// Not a single completed set: only discarding is possible.
    case empty
}

extension ActiveWorkoutModel {
    func finishPrompt() -> FinishPrompt {
        guard let workout = session.workout else { return .confirm }
        let assessment = FinishAssessment(workout: workout, now: workout.startedAt.addingTimeInterval(session.elapsed()))
        if assessment.isEmpty { return .empty }
        if assessment.isShort { return .short(open: assessment.incompleteSets) }
        return assessment.hasOpenSets ? .openSets(assessment.incompleteSets) : .confirm
    }

    /// Records the finished workout really broke: hits whose set is still completed in the stored workout.
    func summaryRecords(for workout: WorkoutSnapshot) -> [PersonalRecordHit] {
        let completed = Set(workout.exercises.flatMap(\.sets).filter(\.input.isCompleted).map(\.id))
        return recordHits.filter { completed.contains($0.setId) }
    }

    /// Display names of the workout's exercises (for the summary screen).
    func exerciseNames(of workout: WorkoutSnapshot) -> [ExerciseRef: String] {
        Dictionary(workout.exercises.map { ($0.ref, name(of: $0.ref)) }, uniquingKeysWith: { first, _ in first })
    }
}

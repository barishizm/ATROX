import Foundation
import SwiftData

/// A realistic, fully deterministic training history for previews, tests and the demo account (no randomness: the same
/// `now` always yields the same data). Four sessions a week for twelve weeks on an upper/lower split, with slow
/// progressive overload. All exercise ids exist in the bundled catalog.
public enum TrainingFixtures {
    public static let weeks = 12
    public static let sessionsPerWeek = 4

    struct Lift {
        let id: String
        let startKg: Double
        /// Added every two weeks.
        let stepKg: Double
        let repsHigh: Int
        let repsLow: Int
    }

    struct Day {
        let name: String
        let lifts: [Lift]
    }

    static let days: [Day] = [
        Day(name: "Upper A", lifts: [
            Lift(id: "barbell-bench-press-medium-grip", startKg: 60, stepKg: 2.5, repsHigh: 8, repsLow: 5),
            Lift(id: "bent-over-barbell-row", startKg: 50, stepKg: 2.5, repsHigh: 8, repsLow: 5),
            Lift(id: "dumbbell-shoulder-press", startKg: 20, stepKg: 1, repsHigh: 10, repsLow: 6),
            Lift(id: "barbell-curl", startKg: 25, stepKg: 1.25, repsHigh: 12, repsLow: 8),
        ]),
        Day(name: "Lower A", lifts: [
            Lift(id: "barbell-squat", startKg: 80, stepKg: 5, repsHigh: 8, repsLow: 5),
            Lift(id: "romanian-deadlift", startKg: 70, stepKg: 5, repsHigh: 10, repsLow: 6),
            Lift(id: "leg-press", startKg: 140, stepKg: 10, repsHigh: 12, repsLow: 8),
        ]),
        Day(name: "Upper B", lifts: [
            Lift(id: "dumbbell-bench-press", startKg: 24, stepKg: 1, repsHigh: 10, repsLow: 6),
            Lift(id: "pullups", startKg: 0, stepKg: 0, repsHigh: 10, repsLow: 6),
            Lift(id: "barbell-shoulder-press", startKg: 35, stepKg: 2.5, repsHigh: 8, repsLow: 5),
            Lift(id: "triceps-pushdown", startKg: 25, stepKg: 2.5, repsHigh: 12, repsLow: 8),
        ]),
        Day(name: "Lower B", lifts: [
            Lift(id: "barbell-deadlift", startKg: 100, stepKg: 5, repsHigh: 6, repsLow: 3),
            Lift(id: "barbell-squat", startKg: 65, stepKg: 5, repsHigh: 10, repsLow: 6),
            Lift(id: "leg-press", startKg: 120, stepKg: 10, repsHigh: 15, repsLow: 10),
        ]),
    ]

    /// Day offsets inside a week: Mon, Tue, Thu, Fri.
    private static let dayOffsets = [0, 1, 3, 4]

    /// The routine the history was "trained from".
    public static func routine(name: String = "Upper / Lower") -> (name: String, days: [(name: String, exercises: [(ref: ExerciseRef, input: RoutineExerciseInput)])]) {
        (
            name,
            days.map { day in
                (
                    day.name,
                    day.lifts.map { lift in
                        (
                            ExerciseRef.catalog(lift.id),
                            RoutineExerciseInput(
                                targetSets: 3, targetRepsMin: lift.repsLow, targetRepsMax: lift.repsHigh, targetRir: 2,
                                restSeconds: 120
                            )
                        )
                    }
                )
            }
        )
    }

    /// 48 finished workouts ending before `now`, oldest first. `routineId` / `dayIds` (one per split day) link them
    /// to a routine when given.
    public static func twelveWeekHistory(
        now: Date, calendar: Calendar = Calendar(identifier: .gregorian), routineId: UUID? = nil, dayIds: [UUID] = []
    ) -> [WorkoutDraft] {
        let today = calendar.startOfDay(for: now)
        var drafts: [WorkoutDraft] = []
        for week in 0..<weeks {
            let weekStart = calendar.date(byAdding: .day, value: -7 * (weeks - week), to: today) ?? today
            for (session, offset) in dayOffsets.enumerated() {
                let sessionIndex = week * sessionsPerWeek + session
                let day = days[session]
                let date = calendar.date(byAdding: .day, value: offset, to: weekStart) ?? weekStart
                let start = calendar.date(byAdding: .hour, value: 18, to: date) ?? date
                let minutes = 55 + (sessionIndex * 7) % 20
                let end = start.addingTimeInterval(TimeInterval(minutes * 60))
                let exercises = day.lifts.enumerated().map { liftIndex, lift in
                    exercise(lift, week: week, sessionIndex: sessionIndex, liftIndex: liftIndex)
                }
                drafts.append(
                    WorkoutDraft(
                        name: day.name, startedAt: start, endedAt: end,
                        routineId: routineId, routineDayId: dayIds.indices.contains(session) ? dayIds[session] : nil,
                        source: routineId == nil ? .manual : .routine, exercises: exercises
                    )
                )
            }
        }
        return drafts
    }

    private static func exercise(_ lift: Lift, week: Int, sessionIndex: Int, liftIndex: Int) -> WorkoutExerciseDraft {
        let weight = lift.startKg + lift.stepKg * Double(week / 2)
        var sets: [SetInput] = []
        if liftIndex == 0, weight > 0 {
            sets.append(SetInput(weightKg: (weight * 0.5 / 2.5).rounded() * 2.5, reps: 8, setType: .warmup, isCompleted: true))
        }
        for index in 0..<3 {
            // Reps drift down a little within the session (fatigue) and up with the cycle position.
            let span = lift.repsHigh - lift.repsLow
            let reps = max(lift.repsLow, lift.repsHigh - (index + week % 2 + sessionIndex % 2) % (span + 1))
            // Every 7th session the last set of the first lift was not finished; it must not count anywhere.
            let skipped = sessionIndex % 7 == 6 && liftIndex == 0 && index == 2
            sets.append(
                SetInput(
                    weightKg: weight, reps: skipped ? 0 : reps, rir: skipped ? nil : 2 - min(index, 2) / 2,
                    setType: .working, isCompleted: !skipped
                )
            )
        }
        return WorkoutExerciseDraft(ref: .catalog(lift.id), sets: sets)
    }

    /// Writes the routine and the twelve-week history for `userId` (previews, demo account).
    public static func seed(_ container: ModelContainer, userId: UUID = DataFixtures.userId, now: Date = Date()) async throws {
        let routines = SwiftDataRoutineRepository(modelContainer: container)
        let workouts = SwiftDataWorkoutRepository(modelContainer: container)
        let template = routine()
        let created = try await routines.create(name: template.name, notes: nil, userId: userId)
        var dayIds: [UUID] = []
        for day in template.days {
            let added = try await routines.addDay(routineId: created.id, name: day.name)
            dayIds.append(added.id)
            for exercise in day.exercises {
                try await routines.addExercise(dayId: added.id, ref: exercise.ref, input: exercise.input)
            }
        }
        for draft in twelveWeekHistory(now: now, routineId: created.id, dayIds: dayIds) {
            try await workouts.start(draft, userId: userId)
        }
    }
}

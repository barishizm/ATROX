import CoachKit
import DataKit
import Foundation

/// What applying a proposal did, for the confirmation under the card.
enum ApplyOutcome: Equatable {
    case routineCreated(id: UUID, name: String)
    case routineChanged(id: UUID, changes: Int)
    case goalUpdated
    case nothingToChange
}

enum ApplyError: Error, Equatable {
    /// The card carries data this app version cannot read.
    case invalidProposal
    case profileMissing
}

/// Turns an accepted proposal into changes in the local stores (docs/04-AI-KOC.md §5): the coach never writes data, the
/// user's tap does, through the same repositories as every other screen (so sync and scores follow as usual).
struct ProposalApplier: Sendable {
    let userId: UUID
    let routines: any RoutineRepository
    let profiles: any ProfileRepository
    let activeRoutineId: @Sendable @MainActor () -> UUID?
    /// Makes a routine the active one (only done when the user has none yet).
    let activate: @Sendable @MainActor (UUID) -> Void

    func apply(_ proposal: CoachProposal) async throws -> ApplyOutcome {
        switch proposal.kind {
        case .routine: try await createRoutine(proposal.data)
        case .routineEdit: try await editRoutine(proposal.data)
        case .exerciseSwap: try await swapExercise(proposal.data)
        case .goalUpdate: try await updateGoal(proposal.data)
        case .memorySaved, .unknown: throw ApplyError.invalidProposal
        }
    }

    // MARK: Routine

    private func createRoutine(_ data: CoachJSON) async throws -> ApplyOutcome {
        guard let name = data["name"]?.string, let days = data["days"]?.array, !days.isEmpty else { throw ApplyError.invalidProposal }
        let routine = try await routines.create(name: name, notes: data["notes"]?.string, userId: userId)
        for day in days {
            guard let dayName = day["name"]?.string else { continue }
            let created = try await routines.addDay(routineId: routine.id, name: dayName)
            for item in day["exercises"]?.array ?? [] {
                guard let prescription = Prescription(item) else { continue }
                try await routines.addExercise(dayId: created.id, ref: prescription.ref, input: prescription.input)
            }
        }
        await MainActor.run {
            if activeRoutineId() == nil { activate(routine.id) }
        }
        return .routineCreated(id: routine.id, name: name)
    }

    // MARK: Edits

    private func editRoutine(_ data: CoachJSON) async throws -> ApplyOutcome {
        guard let routineId = data["routine_id"]?.string.flatMap(UUID.init(uuidString:)), let operations = data["operations"]?.array,
              try await routines.routine(id: routineId) != nil else { throw ApplyError.invalidProposal }
        var changes = 0
        for operation in operations {
            // Positions move after every change, so each operation reads the routine again.
            guard let routine = try await routines.routine(id: routineId),
                  let dayId = operation["day_id"]?.string.flatMap(UUID.init(uuidString:)),
                  let day = routine.days.first(where: { $0.id == dayId }) else { continue }
            if try await perform(operation, on: day) { changes += 1 }
        }
        return changes == 0 ? .nothingToChange : .routineChanged(id: routineId, changes: changes)
    }

    private func perform(_ operation: CoachJSON, on day: RoutineDaySnapshot) async throws -> Bool {
        let existing = operation["exercise_id"]?.string.map(Prescription.ref(for:)).flatMap { ref in day.exercises.first { $0.ref == ref } }
        switch operation["op"]?.string {
        case "add":
            guard let item = operation["exercise"].flatMap(Prescription.init) else { return false }
            try await routines.addExercise(dayId: day.id, ref: item.ref, input: item.input)
            return true
        case "remove":
            guard let existing else { return false }
            try await routines.deleteExercise(id: existing.id)
            return true
        case "replace":
            guard let existing, let item = operation["with"].flatMap(Prescription.init) else { return false }
            try await replace(existing, with: item.ref, input: item.input)
            return true
        case "update":
            guard let existing else { return false }
            var input = existing.input
            if let sets = operation["sets"]?.int { input.targetSets = sets }
            if let low = operation["reps_min"]?.int { input.targetRepsMin = low }
            if let high = operation["reps_max"]?.int { input.targetRepsMax = high }
            try await routines.updateExercise(id: existing.id, with: input)
            return true
        default:
            return false
        }
    }

    private func replace(_ old: RoutineExerciseSnapshot, with ref: ExerciseRef, input: RoutineExerciseInput) async throws {
        let added = try await routines.addExercise(dayId: old.routineDayId, ref: ref, input: input)
        try await routines.moveExercise(id: added.id, to: old.position)
        try await routines.deleteExercise(id: old.id)
    }

    private func swapExercise(_ data: CoachJSON) async throws -> ApplyOutcome {
        guard let from = data["from"]?["id"]?.string, let to = data["to"]?["id"]?.string else { throw ApplyError.invalidProposal }
        let routineId: UUID?
        if let given = data["routine_id"]?.string.flatMap(UUID.init(uuidString:)) {
            routineId = given
        } else {
            routineId = await MainActor.run { activeRoutineId() }
        }
        guard let routineId, let routine = try await routines.routine(id: routineId) else { return .nothingToChange }
        let source = Prescription.ref(for: from)
        var changes = 0
        for day in routine.days {
            for exercise in day.exercises where exercise.ref == source {
                try await replace(exercise, with: Prescription.ref(for: to), input: exercise.input)
                changes += 1
            }
        }
        return changes == 0 ? .nothingToChange : .routineChanged(id: routineId, changes: changes)
    }

    // MARK: Goal

    private func updateGoal(_ data: CoachJSON) async throws -> ApplyOutcome {
        let goal = data["goal"]?.string.flatMap(Goal.init(rawValue:))
        let frequency = data["weekly_frequency"]?.int
        guard goal != nil || frequency != nil else { throw ApplyError.invalidProposal }
        guard var input = try await profiles.profile(userId: userId)?.input else { throw ApplyError.profileMissing }
        if let goal { input.goal = goal }
        if let frequency, (1...7).contains(frequency) { input.weeklyFrequency = frequency }
        try await profiles.upsert(input, userId: userId)
        return .goalUpdated
    }
}

/// One exercise line of a proposal, read defensively from JSON.
struct Prescription: Equatable {
    let ref: ExerciseRef
    let input: RoutineExerciseInput

    init?(_ json: CoachJSON) {
        guard let id = json["exercise_id"]?.string, let sets = json["sets"]?.int,
              let low = json["reps_min"]?.int, let high = json["reps_max"]?.int, low <= high else { return nil }
        ref = Self.ref(for: id)
        input = RoutineExerciseInput(
            targetSets: sets, targetRepsMin: low, targetRepsMax: high, targetRir: json["rir"]?.int,
            restSeconds: json["rest_seconds"]?.int, notes: json["notes"]?.string
        )
    }

    /// A UUID is one of the user's own exercises; everything else is a catalog slug.
    static func ref(for id: String) -> ExerciseRef {
        UUID(uuidString: id).map(ExerciseRef.custom) ?? .catalog(id)
    }
}

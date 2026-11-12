import DataKit
import Foundation
import Observation

/// The user's programs (P033): list, create, duplicate, delete (with undo) and the "active program" choice.
@MainActor
@Observable
final class RoutineListModel {
    enum LoadState: Equatable { case loading, loaded, failed }

    let userId: UUID
    let plan: RoutinePlanStore
    private(set) var loadState: LoadState = .loading
    private(set) var routines: [RoutineSnapshot] = []
    /// The program that was just deleted; the list offers to bring it back.
    private(set) var lastDeleted: RoutineSnapshot?
    var errorOccurred = false

    private let repository: any RoutineRepository

    init(userId: UUID, repository: any RoutineRepository, plan: RoutinePlanStore) {
        self.userId = userId
        self.repository = repository
        self.plan = plan
    }

    func load() async {
        do {
            routines = try await repository.all(userId: userId)
            plan.prune(
                validDayIds: Set(routines.flatMap(\.days).map(\.id)), validRoutineIds: Set(routines.map(\.id))
            )
            loadState = .loaded
        } catch {
            if routines.isEmpty { loadState = .failed } else { errorOccurred = true }
        }
    }

    /// Creates a program with one empty day and returns its id.
    func create(name: String, firstDayName: String) async -> UUID? {
        do {
            let routine = try await repository.create(name: name, notes: nil, userId: userId)
            try await repository.addDay(routineId: routine.id, name: firstDayName)
            if routines.isEmpty { plan.setActive(routine.id) }
            await load()
            return routine.id
        } catch {
            errorOccurred = true
            return nil
        }
    }

    func duplicate(_ id: UUID, name: String) async {
        do {
            _ = try await repository.duplicate(routineId: id, name: name)
            await load()
        } catch {
            errorOccurred = true
        }
    }

    func delete(_ id: UUID) async {
        guard let snapshot = routines.first(where: { $0.id == id }) else { return }
        do {
            try await repository.delete(id: id)
            lastDeleted = snapshot
            await load()
        } catch {
            errorOccurred = true
        }
    }

    func undoDelete() async {
        guard let snapshot = lastDeleted else { return }
        lastDeleted = nil
        do {
            try await repository.restore(snapshot)
            await load()
        } catch {
            errorOccurred = true
        }
    }

    func dismissUndo() { lastDeleted = nil }

    func setActive(_ id: UUID) { plan.setActive(id) }
}

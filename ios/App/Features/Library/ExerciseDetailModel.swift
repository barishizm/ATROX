import DataKit
import Foundation
import Observation
import SwiftData

/// State of one exercise's detail screen (P031): loads the catalog or custom exercise, and lets the user edit or
/// delete one of their own.
@MainActor
@Observable
final class ExerciseDetailModel {
    enum LoadState: Equatable { case loading, loaded(ExerciseDetail), missing, failed }

    let id: String
    let userId: UUID?
    private(set) var state: LoadState = .loading
    /// "tr" / "en"; follows the app language.
    var languageCode = "en"
    private let modelContainer: ModelContainer
    private let repository: any CustomExerciseRepository

    init(
        id: String, modelContainer: ModelContainer, userId: UUID?,
        repository: (any CustomExerciseRepository)? = nil
    ) {
        self.id = id
        self.modelContainer = modelContainer
        self.userId = userId
        self.repository = repository ?? SwiftDataCustomExerciseRepository(modelContainer: modelContainer)
    }

    var detail: ExerciseDetail? {
        if case .loaded(let detail) = state { return detail }
        return nil
    }

    /// Only the user's own exercises can be edited or deleted.
    var canManage: Bool { (detail?.isCustom ?? false) && userId != nil }

    func load() async {
        let container = modelContainer, id = id
        do {
            let found = try await Task.detached { try ExerciseDetail.load(id: id, in: container) }.value
            state = found.map(LoadState.loaded) ?? .missing
        } catch {
            state = .failed
        }
    }

    /// The editable form of this custom exercise.
    func customSnapshot() async -> CustomExerciseSnapshot? {
        guard canManage, let uuid = UUID(uuidString: id) else { return nil }
        return try? await repository.exercise(id: uuid)
    }

    /// Soft-deletes the custom exercise; false when it could not be deleted.
    func delete() async -> Bool {
        guard canManage, let uuid = UUID(uuidString: id) else { return false }
        do {
            try await repository.delete(id: uuid)
            state = .missing
            return true
        } catch {
            return false
        }
    }

    /// Repository handed to the edit form.
    var customRepository: any CustomExerciseRepository { repository }
}

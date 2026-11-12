import Foundation
import SwiftData

@ModelActor
public actor SwiftDataCustomExerciseRepository: CustomExerciseRepository {
    private var clock: @Sendable () -> Date = { Date() }

    public init(modelContainer: ModelContainer, clock: @escaping @Sendable () -> Date) {
        self.modelExecutor = DefaultSerialModelExecutor(modelContext: ModelContext(modelContainer))
        self.modelContainer = modelContainer
        self.clock = clock
    }

    @discardableResult
    public func create(_ input: CustomExerciseInput, userId: UUID) throws -> CustomExerciseSnapshot {
        let model = CustomExercise(userId: userId, input: try input.validated(), now: clock())
        modelContext.insert(model)
        try modelContext.save()
        return model.snapshot
    }

    @discardableResult
    public func update(id: UUID, with input: CustomExerciseInput) throws -> CustomExerciseSnapshot {
        let valid = try input.validated()
        guard let model = try fetch(id: id), !model.isSoftDeleted else { throw DataError.notFound }
        model.apply(valid)
        model.markPending(at: clock())
        try modelContext.save()
        return model.snapshot
    }

    public func delete(id: UUID) throws {
        guard let model = try fetch(id: id), !model.isSoftDeleted else { throw DataError.notFound }
        model.markDeleted(at: clock())
        try modelContext.save()
    }

    public func exercise(id: UUID) throws -> CustomExerciseSnapshot? {
        try fetch(id: id).flatMap { $0.isSoftDeleted ? nil : $0.snapshot }
    }

    public func all(userId: UUID) throws -> [CustomExerciseSnapshot] {
        let descriptor = FetchDescriptor<CustomExercise>(
            predicate: #Predicate { $0.userId == userId && $0.deletedAt == nil }, sortBy: [SortDescriptor(\.name)]
        )
        return try modelContext.fetch(descriptor).map(\.snapshot)
    }

    private func fetch(id: UUID) throws -> CustomExercise? {
        var descriptor = FetchDescriptor<CustomExercise>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }
}

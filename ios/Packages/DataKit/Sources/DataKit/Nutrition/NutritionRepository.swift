import Foundation
import SwiftData

public protocol NutritionRepository: Sendable {
    @discardableResult
    func add(_ input: FoodEntryInput, userId: UUID) async throws -> FoodEntrySnapshot
    @discardableResult
    func update(id: UUID, with input: FoodEntryInput) async throws -> FoodEntrySnapshot
    func delete(id: UUID) async throws
    /// Entries eaten in `[start, end)`, oldest first.
    func entries(userId: UUID, from start: Date, to end: Date) async throws -> [FoodEntrySnapshot]
    func target(userId: UUID) async throws -> NutritionTargetInput?
    @discardableResult
    func setTarget(_ input: NutritionTargetInput, userId: UUID) async throws -> NutritionTargetInput
}

@ModelActor
public actor SwiftDataNutritionRepository: NutritionRepository {
    private var clock: @Sendable () -> Date = { Date() }

    public init(modelContainer: ModelContainer, clock: @escaping @Sendable () -> Date) {
        self.modelExecutor = DefaultSerialModelExecutor(modelContext: ModelContext(modelContainer))
        self.modelContainer = modelContainer
        self.clock = clock
    }

    @discardableResult
    public func add(_ input: FoodEntryInput, userId: UUID) throws -> FoodEntrySnapshot {
        try validate(input)
        let model = FoodEntry(userId: userId, input: input, now: clock())
        modelContext.insert(model)
        try modelContext.save()
        return model.snapshot
    }

    @discardableResult
    public func update(id: UUID, with input: FoodEntryInput) throws -> FoodEntrySnapshot {
        try validate(input)
        guard let model = try fetch(id: id), !model.isSoftDeleted else { throw DataError.notFound }
        model.apply(input)
        model.markPending(at: clock())
        try modelContext.save()
        return model.snapshot
    }

    public func delete(id: UUID) throws {
        guard let model = try fetch(id: id), !model.isSoftDeleted else { throw DataError.notFound }
        model.markDeleted(at: clock())
        try modelContext.save()
    }

    public func entries(userId: UUID, from start: Date, to end: Date) throws -> [FoodEntrySnapshot] {
        let descriptor = FetchDescriptor<FoodEntry>(
            predicate: #Predicate { $0.userId == userId && $0.deletedAt == nil && $0.eatenAt >= start && $0.eatenAt < end },
            sortBy: [SortDescriptor(\.eatenAt)]
        )
        return try modelContext.fetch(descriptor).map(\.snapshot)
    }

    public func target(userId: UUID) throws -> NutritionTargetInput? {
        guard let model = try fetchTarget(userId: userId), !model.isSoftDeleted else { return nil }
        return model.input
    }

    @discardableResult
    public func setTarget(_ input: NutritionTargetInput, userId: UUID) throws -> NutritionTargetInput {
        let values = input.values
        guard (800...10_000).contains(values.calories) else { throw DataError.invalidValue("calories") }
        guard (0...1000).contains(values.proteinG), (0...2000).contains(values.carbsG), (0...1000).contains(values.fatG) else {
            throw DataError.invalidValue("macros")
        }
        let now = clock()
        if let model = try fetchTarget(userId: userId) {
            model.apply(input)
            model.deletedAt = nil
            model.markPending(at: now)
        } else {
            modelContext.insert(NutritionTarget(userId: userId, input: input, now: now))
        }
        try modelContext.save()
        return input
    }

    private func fetch(id: UUID) throws -> FoodEntry? {
        var descriptor = FetchDescriptor<FoodEntry>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    private func fetchTarget(userId: UUID) throws -> NutritionTarget? {
        var descriptor = FetchDescriptor<NutritionTarget>(predicate: #Predicate { $0.userId == userId })
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    private func validate(_ input: FoodEntryInput) throws {
        guard !input.name.trimmingCharacters(in: .whitespaces).isEmpty, input.name.count <= 120 else { throw DataError.invalidValue("name") }
        guard (0...20_000).contains(input.calories) else { throw DataError.invalidValue("calories") }
        guard (0...2000).contains(input.proteinG), (0...2000).contains(input.carbsG), (0...2000).contains(input.fatG) else {
            throw DataError.invalidValue("macros")
        }
        if let grams = input.grams, !(0...20_000).contains(grams) { throw DataError.invalidValue("grams") }
    }
}

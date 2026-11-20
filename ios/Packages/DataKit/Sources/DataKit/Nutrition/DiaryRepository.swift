import Foundation
import SwiftData

public protocol DiaryRepository: Sendable {
    @discardableResult
    func add(_ input: DiaryLogInput, userId: UUID) async throws -> DiaryLogSnapshot
    @discardableResult
    func update(id: UUID, with input: DiaryLogInput) async throws -> DiaryLogSnapshot
    func delete(id: UUID) async throws
    /// Logs of the given kinds with `at` in `[start, end)`, oldest first.
    func logs(userId: UUID, kinds: Set<DiaryLogKind>, from start: Date, to end: Date) async throws -> [DiaryLogSnapshot]
    /// The most recent log of a kind (by `at`), if any.
    func latest(userId: UUID, kind: DiaryLogKind) async throws -> DiaryLogSnapshot?
}

@ModelActor
public actor SwiftDataDiaryRepository: DiaryRepository {
    private var clock: @Sendable () -> Date = { Date() }

    public init(modelContainer: ModelContainer, clock: @escaping @Sendable () -> Date) {
        self.modelExecutor = DefaultSerialModelExecutor(modelContext: ModelContext(modelContainer))
        self.modelContainer = modelContainer
        self.clock = clock
    }

    @discardableResult
    public func add(_ input: DiaryLogInput, userId: UUID) throws -> DiaryLogSnapshot {
        guard DiaryLogLimits.isValid(input) else { throw DataError.invalidValue(input.kind.rawValue) }
        let model = DiaryLog(userId: userId, input: input, now: clock())
        modelContext.insert(model)
        try modelContext.save()
        return model.snapshot
    }

    @discardableResult
    public func update(id: UUID, with input: DiaryLogInput) throws -> DiaryLogSnapshot {
        guard DiaryLogLimits.isValid(input) else { throw DataError.invalidValue(input.kind.rawValue) }
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

    public func logs(userId: UUID, kinds: Set<DiaryLogKind>, from start: Date, to end: Date) throws -> [DiaryLogSnapshot] {
        let raws = kinds.map(\.rawValue)
        let descriptor = FetchDescriptor<DiaryLog>(
            predicate: #Predicate { $0.userId == userId && $0.deletedAt == nil && $0.at >= start && $0.at < end && raws.contains($0.kindRaw) },
            sortBy: [SortDescriptor(\.at)]
        )
        return try modelContext.fetch(descriptor).map(\.snapshot)
    }

    public func latest(userId: UUID, kind: DiaryLogKind) throws -> DiaryLogSnapshot? {
        let raw = kind.rawValue
        var descriptor = FetchDescriptor<DiaryLog>(
            predicate: #Predicate { $0.userId == userId && $0.deletedAt == nil && $0.kindRaw == raw },
            sortBy: [SortDescriptor(\.at, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first?.snapshot
    }

    private func fetch(id: UUID) throws -> DiaryLog? {
        var descriptor = FetchDescriptor<DiaryLog>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }
}

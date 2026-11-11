import Foundation
import SwiftData

/// `@ModelActor` implementations. Each owns its own `ModelContext`, so work stays off the main actor.
/// `clock` is injectable so tests can assert `updatedAt` precisely.

@ModelActor
public actor SwiftDataProfileRepository: ProfileRepository {
    private var clock: @Sendable () -> Date = { Date() }

    public init(modelContainer: ModelContainer, clock: @escaping @Sendable () -> Date) {
        self.modelExecutor = DefaultSerialModelExecutor(modelContext: ModelContext(modelContainer))
        self.modelContainer = modelContainer
        self.clock = clock
    }

    public func profile(userId: UUID) throws -> ProfileSnapshot? {
        try fetch(userId: userId).flatMap { $0.isSoftDeleted ? nil : $0.snapshot }
    }

    @discardableResult
    public func upsert(_ input: ProfileInput, userId: UUID) throws -> ProfileSnapshot {
        guard (100...250).contains(input.heightCm) else { throw DataError.invalidValue("heightCm") }
        guard (1...7).contains(input.weeklyFrequency) else { throw DataError.invalidValue("weeklyFrequency") }
        let now = clock()
        let model: UserProfile
        if let existing = try fetch(userId: userId) {
            existing.apply(input)
            existing.deletedAt = nil
            existing.markPending(at: now)
            model = existing
        } else {
            model = UserProfile(userId: userId, input: input, now: now)
            modelContext.insert(model)
        }
        try modelContext.save()
        return model.snapshot
    }

    public func delete(userId: UUID) throws {
        guard let model = try fetch(userId: userId), !model.isSoftDeleted else { throw DataError.notFound }
        model.markDeleted(at: clock())
        try modelContext.save()
    }

    private func fetch(userId: UUID) throws -> UserProfile? {
        var descriptor = FetchDescriptor<UserProfile>(predicate: #Predicate { $0.userId == userId })
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }
}

@ModelActor
public actor SwiftDataMeasurementRepository: MeasurementRepository {
    private var clock: @Sendable () -> Date = { Date() }

    public init(modelContainer: ModelContainer, clock: @escaping @Sendable () -> Date) {
        self.modelExecutor = DefaultSerialModelExecutor(modelContext: ModelContext(modelContainer))
        self.modelContainer = modelContainer
        self.clock = clock
    }

    @discardableResult
    public func add(_ input: MeasurementInput, userId: UUID) throws -> MeasurementSnapshot {
        try validate(input)
        let model = BodyMeasurement(userId: userId, input: input, now: clock())
        modelContext.insert(model)
        try modelContext.save()
        return model.snapshot
    }

    @discardableResult
    public func update(id: UUID, with input: MeasurementInput) throws -> MeasurementSnapshot {
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

    public func all(userId: UUID) throws -> [MeasurementSnapshot] {
        let descriptor = FetchDescriptor<BodyMeasurement>(
            predicate: #Predicate { $0.userId == userId && $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.date, order: .reverse), SortDescriptor(\.createdAt, order: .reverse)]
        )
        return try modelContext.fetch(descriptor).map(\.snapshot)
    }

    public func latest(userId: UUID) throws -> MeasurementSnapshot? {
        try all(userId: userId).first
    }

    private func fetch(id: UUID) throws -> BodyMeasurement? {
        var descriptor = FetchDescriptor<BodyMeasurement>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    private func validate(_ input: MeasurementInput) throws {
        guard (20...400).contains(input.weightKg) else { throw DataError.invalidValue("weightKg") }
        if let fat = input.bodyFatPct, !(2...70).contains(fat) { throw DataError.invalidValue("bodyFatPct") }
    }
}

@ModelActor
public actor SwiftDataConsentRepository: ConsentRepository {
    private var clock: @Sendable () -> Date = { Date() }

    public init(modelContainer: ModelContainer, clock: @escaping @Sendable () -> Date) {
        self.modelExecutor = DefaultSerialModelExecutor(modelContext: ModelContext(modelContainer))
        self.modelContainer = modelContainer
        self.clock = clock
    }

    @discardableResult
    public func record(kind: ConsentKind, version: String, granted: Bool, userId: UUID) throws -> ConsentSnapshot {
        let model = ConsentRecord(userId: userId, kind: kind, version: version, granted: granted, now: clock())
        modelContext.insert(model)
        try modelContext.save()
        return model.snapshot
    }

    public func current(kind: ConsentKind, userId: UUID) throws -> ConsentSnapshot? {
        let raw = kind.rawValue
        var descriptor = FetchDescriptor<ConsentRecord>(
            predicate: #Predicate { $0.userId == userId && $0.kindRaw == raw },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first?.snapshot
    }

    public func history(userId: UUID) throws -> [ConsentSnapshot] {
        let descriptor = FetchDescriptor<ConsentRecord>(
            predicate: #Predicate { $0.userId == userId },
            sortBy: [SortDescriptor(\.createdAt)]
        )
        return try modelContext.fetch(descriptor).map(\.snapshot)
    }
}

@ModelActor
public actor SwiftDataSettingsRepository: SettingsRepository {
    private var clock: @Sendable () -> Date = { Date() }

    public init(modelContainer: ModelContainer, clock: @escaping @Sendable () -> Date) {
        self.modelExecutor = DefaultSerialModelExecutor(modelContext: ModelContext(modelContainer))
        self.modelContainer = modelContainer
        self.clock = clock
    }

    @discardableResult
    public func settings(userId: UUID) throws -> SettingsSnapshot {
        if let existing = try fetch(userId: userId) {
            if existing.isSoftDeleted {
                existing.deletedAt = nil
                existing.markPending(at: clock())
                try modelContext.save()
            }
            return existing.snapshot
        }
        let model = UserSettings(userId: userId, now: clock())
        modelContext.insert(model)
        try modelContext.save()
        return model.snapshot
    }

    @discardableResult
    public func update(_ input: SettingsInput, userId: UUID) throws -> SettingsSnapshot {
        guard (10...600).contains(input.restTimerSeconds) else { throw DataError.invalidValue("restTimerSeconds") }
        guard (0...50).contains(input.defaultBarKg) else { throw DataError.invalidValue("defaultBarKg") }
        let now = clock()
        let model: UserSettings
        if let existing = try fetch(userId: userId) {
            existing.apply(input)
            existing.deletedAt = nil
            existing.markPending(at: now)
            model = existing
        } else {
            model = UserSettings(userId: userId, now: now)
            model.apply(input)
            modelContext.insert(model)
        }
        try modelContext.save()
        return model.snapshot
    }

    private func fetch(userId: UUID) throws -> UserSettings? {
        var descriptor = FetchDescriptor<UserSettings>(predicate: #Predicate { $0.userId == userId })
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }
}

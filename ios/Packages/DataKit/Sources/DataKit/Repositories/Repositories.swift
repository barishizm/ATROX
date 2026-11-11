import Foundation

/// Repository contracts. Every write sets `updatedAt` and `syncState = .pending` (docs/02-MIMARI.md §2.4).
/// Reads hide soft-deleted rows.

public protocol ProfileRepository: Sendable {
    func profile(userId: UUID) async throws -> ProfileSnapshot?
    /// Creates the user's profile or replaces its fields (also revives a soft-deleted one).
    @discardableResult
    func upsert(_ input: ProfileInput, userId: UUID) async throws -> ProfileSnapshot
    func delete(userId: UUID) async throws
}

public protocol MeasurementRepository: Sendable {
    @discardableResult
    func add(_ input: MeasurementInput, userId: UUID) async throws -> MeasurementSnapshot
    @discardableResult
    func update(id: UUID, with input: MeasurementInput) async throws -> MeasurementSnapshot
    func delete(id: UUID) async throws
    /// Newest day first.
    func all(userId: UUID) async throws -> [MeasurementSnapshot]
    func latest(userId: UUID) async throws -> MeasurementSnapshot?
}

public protocol ConsentRepository: Sendable {
    /// Appends a row; earlier rows are kept as the audit trail.
    @discardableResult
    func record(kind: ConsentKind, version: String, granted: Bool, userId: UUID) async throws -> ConsentSnapshot
    /// Latest row for the kind, i.e. the current state.
    func current(kind: ConsentKind, userId: UUID) async throws -> ConsentSnapshot?
    /// Oldest first.
    func history(userId: UUID) async throws -> [ConsentSnapshot]
}

public protocol SettingsRepository: Sendable {
    /// The user's settings; the row is created with the defaults on first read.
    @discardableResult
    func settings(userId: UUID) async throws -> SettingsSnapshot
    @discardableResult
    func update(_ input: SettingsInput, userId: UUID) async throws -> SettingsSnapshot
}

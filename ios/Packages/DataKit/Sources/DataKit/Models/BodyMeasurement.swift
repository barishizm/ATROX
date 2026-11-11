import Foundation
import SwiftData

extension SchemaV1 {
    /// Weight (and optional body fat) on a given day. Mirrors `public.body_measurements`.
    @Model
    public final class BodyMeasurement: SyncableRecord {
        @Attribute(.unique) public var id: UUID
        public var userId: UUID
        public var createdAt: Date
        public var updatedAt: Date
        public var deletedAt: Date?
        public var syncStateRaw: String

        public var date: Date
        public var weightKg: Double
        public var bodyFatPct: Double?
        public var sourceRaw: String

        public var source: MeasurementSource {
            get { MeasurementSource(rawValue: sourceRaw) ?? .manual }
            set { sourceRaw = newValue.rawValue }
        }

        public init(id: UUID = UUID(), userId: UUID, input: MeasurementInput, now: Date = Date()) {
            self.id = id
            self.userId = userId
            self.createdAt = now
            self.updatedAt = now
            self.deletedAt = nil
            self.syncStateRaw = SyncState.pending.rawValue
            self.date = input.date
            self.weightKg = input.weightKg
            self.bodyFatPct = input.bodyFatPct
            self.sourceRaw = input.source.rawValue
        }

        func apply(_ input: MeasurementInput) {
            date = input.date
            weightKg = input.weightKg
            bodyFatPct = input.bodyFatPct
            source = input.source
        }
    }
}

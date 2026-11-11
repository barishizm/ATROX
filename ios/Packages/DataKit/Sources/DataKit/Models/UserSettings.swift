import Foundation
import SwiftData

extension SchemaV1 {
    /// One row per user. Mirrors `public.user_settings`; defaults match the column defaults.
    @Model
    public final class UserSettings: SyncableRecord {
        @Attribute(.unique) public var id: UUID
        public var userId: UUID
        public var createdAt: Date
        public var updatedAt: Date
        public var deletedAt: Date?
        public var syncStateRaw: String

        public var themeRaw: String
        public var weightUnitRaw: String
        public var lengthUnitRaw: String
        public var referenceGroupRaw: String
        public var rirEnabled: Bool
        public var restTimerSeconds: Int
        public var defaultBarKg: Double
        /// Plates are stored in kg like every other weight.
        public var availablePlatesKg: [Double]

        public var theme: ThemePreference {
            get { ThemePreference(rawValue: themeRaw) ?? .system }
            set { themeRaw = newValue.rawValue }
        }
        public var weightUnit: WeightUnit {
            get { WeightUnit(rawValue: weightUnitRaw) ?? .kg }
            set { weightUnitRaw = newValue.rawValue }
        }
        public var lengthUnit: LengthUnit {
            get { LengthUnit(rawValue: lengthUnitRaw) ?? .cm }
            set { lengthUnitRaw = newValue.rawValue }
        }
        public var referenceGroup: ReferenceGroup {
            get { ReferenceGroup(rawValue: referenceGroupRaw) ?? .gym }
            set { referenceGroupRaw = newValue.rawValue }
        }

        public init(id: UUID = UUID(), userId: UUID, now: Date = Date()) {
            self.id = id
            self.userId = userId
            self.createdAt = now
            self.updatedAt = now
            self.deletedAt = nil
            self.syncStateRaw = SyncState.pending.rawValue
            self.themeRaw = ThemePreference.system.rawValue
            self.weightUnitRaw = WeightUnit.kg.rawValue
            self.lengthUnitRaw = LengthUnit.cm.rawValue
            self.referenceGroupRaw = ReferenceGroup.gym.rawValue
            self.rirEnabled = true
            self.restTimerSeconds = 120
            self.defaultBarKg = 20
            self.availablePlatesKg = [1.25, 2.5, 5, 10, 15, 20, 25]
        }

        func apply(_ input: SettingsInput) {
            theme = input.theme
            weightUnit = input.weightUnit
            lengthUnit = input.lengthUnit
            referenceGroup = input.referenceGroup
            rirEnabled = input.rirEnabled
            restTimerSeconds = input.restTimerSeconds
            defaultBarKg = input.defaultBarKg
            availablePlatesKg = input.availablePlatesKg
        }
    }
}

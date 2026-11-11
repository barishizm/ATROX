import Foundation
import SwiftData

extension SchemaV1 {
    /// One row per user. Mirrors `public.profiles`.
    @Model
    public final class UserProfile: SyncableRecord {
        @Attribute(.unique) public var id: UUID
        public var userId: UUID
        public var createdAt: Date
        public var updatedAt: Date
        public var deletedAt: Date?
        public var syncStateRaw: String

        public var firstName: String?
        public var lastName: String?
        public var birthDate: Date
        public var sexRaw: String
        public var heightCm: Double
        public var unitSystemRaw: String
        public var experienceRaw: String
        public var goalRaw: String
        public var weeklyFrequency: Int
        public var equipmentAccessRaw: String
        public var limitations: [String]
        public var locale: String

        public var sex: Sex {
            get { Sex(rawValue: sexRaw) ?? .unspecified }
            set { sexRaw = newValue.rawValue }
        }
        public var unitSystem: UnitSystem {
            get { UnitSystem(rawValue: unitSystemRaw) ?? .metric }
            set { unitSystemRaw = newValue.rawValue }
        }
        public var experience: Experience {
            get { Experience(rawValue: experienceRaw) ?? .noExperience }
            set { experienceRaw = newValue.rawValue }
        }
        public var goal: Goal {
            get { Goal(rawValue: goalRaw) ?? .generalHealth }
            set { goalRaw = newValue.rawValue }
        }
        public var equipmentAccess: EquipmentAccess {
            get { EquipmentAccess(rawValue: equipmentAccessRaw) ?? .fullGym }
            set { equipmentAccessRaw = newValue.rawValue }
        }

        public init(id: UUID = UUID(), userId: UUID, input: ProfileInput, now: Date = Date()) {
            self.id = id
            self.userId = userId
            self.createdAt = now
            self.updatedAt = now
            self.deletedAt = nil
            self.syncStateRaw = SyncState.pending.rawValue
            self.firstName = input.firstName
            self.lastName = input.lastName
            self.birthDate = input.birthDate
            self.sexRaw = input.sex.rawValue
            self.heightCm = input.heightCm
            self.unitSystemRaw = input.unitSystem.rawValue
            self.experienceRaw = input.experience.rawValue
            self.goalRaw = input.goal.rawValue
            self.weeklyFrequency = input.weeklyFrequency
            self.equipmentAccessRaw = input.equipmentAccess.rawValue
            self.limitations = input.limitations
            self.locale = input.locale
        }

        func apply(_ input: ProfileInput) {
            firstName = input.firstName
            lastName = input.lastName
            birthDate = input.birthDate
            sex = input.sex
            heightCm = input.heightCm
            unitSystem = input.unitSystem
            experience = input.experience
            goal = input.goal
            weeklyFrequency = input.weeklyFrequency
            equipmentAccess = input.equipmentAccess
            limitations = input.limitations
            locale = input.locale
        }
    }
}

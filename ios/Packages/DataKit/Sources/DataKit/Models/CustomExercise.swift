import Foundation
import SwiftData

extension SchemaV3 {
    /// An exercise the user created. Same descriptor fields as the catalog's `Exercise`, but a single name (in the
    /// language the user typed it) and a syncable row. Mirrors `public.custom_exercises`.
    @Model
    public final class CustomExercise: SyncableRecord {
        @Attribute(.unique) public var id: UUID
        public var userId: UUID
        public var createdAt: Date
        public var updatedAt: Date
        public var deletedAt: Date?
        public var syncStateRaw: String

        public var name: String
        public var aliases: [String]
        public var instructions: [String]
        public var equipment: String?
        public var mechanic: String?
        public var force: String?
        public var level: String
        public var category: String
        public var primaryMuscles: [String]
        public var secondaryMuscles: [String]
        public var movementPattern: String
        public var isUnilateral: Bool

        public var scoringTypeRaw: String
        public var anchorLift: String?
        public var loadConvention: String?
        public var ratio: Double?
        public var tau: Double?
        public var ratioConfidence: String?
        public var bwFraction: Double?

        public init(id: UUID = UUID(), userId: UUID, input: CustomExerciseInput, now: Date = Date()) {
            self.id = id
            self.userId = userId
            createdAt = now
            updatedAt = now
            deletedAt = nil
            syncStateRaw = SyncState.pending.rawValue
            name = input.name
            aliases = input.aliases
            instructions = input.instructions
            equipment = input.equipment
            mechanic = input.mechanic
            force = nil
            level = input.level
            category = "strength"
            primaryMuscles = input.primaryMuscles
            secondaryMuscles = input.secondaryMuscles
            movementPattern = input.movementPattern
            isUnilateral = input.isUnilateral
            scoringTypeRaw = input.scoring.type
            anchorLift = input.scoring.anchorLift
            loadConvention = input.scoring.loadConvention
            ratio = input.scoring.ratio
            tau = input.scoring.tau
            ratioConfidence = input.scoring.ratioConfidence
            bwFraction = input.scoring.bwFraction
        }

        func apply(_ input: CustomExerciseInput) {
            name = input.name
            aliases = input.aliases
            instructions = input.instructions
            equipment = input.equipment
            mechanic = input.mechanic
            level = input.level
            primaryMuscles = input.primaryMuscles
            secondaryMuscles = input.secondaryMuscles
            movementPattern = input.movementPattern
            isUnilateral = input.isUnilateral
            scoringTypeRaw = input.scoring.type
            anchorLift = input.scoring.anchorLift
            loadConvention = input.scoring.loadConvention
            ratio = input.scoring.ratio
            tau = input.scoring.tau
            ratioConfidence = input.scoring.ratioConfidence
            bwFraction = input.scoring.bwFraction
        }
    }
}

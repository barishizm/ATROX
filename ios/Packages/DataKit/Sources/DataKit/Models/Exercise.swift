import Foundation
import SwiftData

extension SchemaV2 {
    /// One catalog exercise (read-only, shared by all users). `id` is the stable slug from `id_lock.json`; it never
    /// changes, and an exercise removed from the catalog is archived (`isArchived`) rather than deleted, so history
    /// that references it keeps working. Mirrors `public.exercises` + `exercise_translations`.
    @Model
    public final class Exercise {
        @Attribute(.unique) public var id: String

        public var nameEn: String
        public var nameTr: String
        public var aliasesEn: [String]
        public var aliasesTr: [String]
        public var instructionsEn: [String]
        public var instructionsTr: [String]
        /// Accent-, case- and Turkish-i-folded names + aliases of both languages (see `SearchFolding`).
        public var searchText: String

        public var equipment: String?
        public var mechanic: String?
        public var force: String?
        public var level: String
        public var category: String
        public var primaryMuscles: [String]
        public var secondaryMuscles: [String]
        public var movementPattern: String

        public var scoringTypeRaw: String
        public var anchorLift: String?
        public var loadConvention: String?
        public var ratio: Double?
        public var tau: Double?
        public var ratioConfidence: String?
        public var bwFraction: Double?
        public var isCore: Bool
        public var isUnilateral: Bool

        /// Full-size image file names in Supabase Storage (`exercise-images`); the thumbnail is `ImageNaming.thumb`.
        public var imagePaths: [String]
        public var isArchived: Bool

        init(record: CatalogRecord) {
            id = record.id
            nameEn = ""; nameTr = ""
            aliasesEn = []; aliasesTr = []
            instructionsEn = []; instructionsTr = []
            searchText = ""
            equipment = nil; mechanic = nil; force = nil
            level = record.level
            category = record.category
            primaryMuscles = []; secondaryMuscles = []
            movementPattern = record.movementPattern
            scoringTypeRaw = record.scoringType
            isCore = record.isCore
            isUnilateral = record.isUnilateral
            imagePaths = []
            isArchived = false
            apply(record)
        }

        func apply(_ record: CatalogRecord) {
            let en = record.translations["en"], tr = record.translations["tr"]
            nameEn = en?.name ?? tr?.name ?? record.id
            nameTr = tr?.name ?? en?.name ?? record.id
            aliasesEn = en?.aliases ?? []
            aliasesTr = tr?.aliases ?? []
            instructionsEn = en?.instructions ?? []
            instructionsTr = tr?.instructions ?? []
            searchText = SearchFolding.fold(([nameEn, nameTr] + aliasesEn + aliasesTr).joined(separator: " "))
            equipment = record.equipment
            mechanic = record.mechanic
            force = record.force
            level = record.level
            category = record.category
            primaryMuscles = record.primaryMuscles
            secondaryMuscles = record.secondaryMuscles
            movementPattern = record.movementPattern
            scoringTypeRaw = record.scoringType
            anchorLift = record.anchorLift
            loadConvention = record.loadConvention
            ratio = record.ratio
            tau = record.tau
            ratioConfidence = record.ratioConfidence
            bwFraction = record.bwFraction
            isCore = record.isCore
            isUnilateral = record.isUnilateral
            imagePaths = record.images
            isArchived = record.archived
        }

        /// Name in the given language code ("tr", "en", ...); falls back to English.
        public func name(languageCode: String) -> String { languageCode == "tr" ? nameTr : nameEn }
    }

    /// Single bookkeeping row: which catalog version is installed and when it was imported / last synced.
    @Model
    public final class CatalogInfo {
        public static let rowKey = "catalog"

        @Attribute(.unique) public var key: String
        public var version: Int
        public var checksum: String
        public var importedAt: Date
        public var syncedAt: Date?

        init(version: Int, checksum: String, importedAt: Date) {
            key = Self.rowKey
            self.version = version
            self.checksum = checksum
            self.importedAt = importedAt
        }
    }
}

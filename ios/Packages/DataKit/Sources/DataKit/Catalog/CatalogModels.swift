import Foundation

/// Decoded form of one exercise, shared by the bundled `catalog.v{N}.json` and the Supabase tables.
public struct CatalogRecord: Sendable, Equatable, Decodable {
    public struct Translation: Sendable, Equatable, Decodable {
        public var name: String
        public var aliases: [String]
        public var instructions: [String]

        public init(name: String, aliases: [String] = [], instructions: [String] = []) {
            self.name = name
            self.aliases = aliases
            self.instructions = instructions
        }
    }

    public var id: String
    public var equipment: String?
    public var mechanic: String?
    public var force: String?
    public var level: String
    public var category: String
    public var primaryMuscles: [String]
    public var secondaryMuscles: [String]
    public var movementPattern: String
    public var scoringType: String
    public var anchorLift: String?
    public var loadConvention: String?
    public var ratio: Double?
    public var tau: Double?
    public var ratioConfidence: String?
    public var bwFraction: Double?
    public var isCore: Bool
    public var isUnilateral: Bool
    public var images: [String]
    public var translations: [String: Translation]
    /// Only the server can say an exercise is archived; the bundled file never contains archived ones.
    public var archived: Bool

    public init(
        id: String, equipment: String? = nil, mechanic: String? = nil, force: String? = nil,
        level: String = "beginner", category: String = "strength", primaryMuscles: [String] = ["chest"],
        secondaryMuscles: [String] = [], movementPattern: String = "other", scoringType: String = "none",
        anchorLift: String? = nil, loadConvention: String? = nil, ratio: Double? = nil, tau: Double? = nil,
        ratioConfidence: String? = nil, bwFraction: Double? = nil, isCore: Bool = false, isUnilateral: Bool = false,
        images: [String] = [], translations: [String: Translation], archived: Bool = false
    ) {
        self.id = id; self.equipment = equipment; self.mechanic = mechanic; self.force = force
        self.level = level; self.category = category
        self.primaryMuscles = primaryMuscles; self.secondaryMuscles = secondaryMuscles
        self.movementPattern = movementPattern; self.scoringType = scoringType
        self.anchorLift = anchorLift; self.loadConvention = loadConvention
        self.ratio = ratio; self.tau = tau; self.ratioConfidence = ratioConfidence; self.bwFraction = bwFraction
        self.isCore = isCore; self.isUnilateral = isUnilateral
        self.images = images; self.translations = translations; self.archived = archived
    }

    private enum CodingKeys: String, CodingKey {
        case id, equipment, mechanic, force, level, category, primaryMuscles, secondaryMuscles, movementPattern
        case scoringType, anchorLift, loadConvention, ratio, tau, ratioConfidence, bwFraction, isCore, isUnilateral
        case images, translations, archived
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        equipment = try c.decodeIfPresent(String.self, forKey: .equipment)
        mechanic = try c.decodeIfPresent(String.self, forKey: .mechanic)
        force = try c.decodeIfPresent(String.self, forKey: .force)
        level = try c.decode(String.self, forKey: .level)
        category = try c.decode(String.self, forKey: .category)
        primaryMuscles = try c.decode([String].self, forKey: .primaryMuscles)
        secondaryMuscles = try c.decodeIfPresent([String].self, forKey: .secondaryMuscles) ?? []
        movementPattern = try c.decode(String.self, forKey: .movementPattern)
        scoringType = try c.decode(String.self, forKey: .scoringType)
        anchorLift = try c.decodeIfPresent(String.self, forKey: .anchorLift)
        loadConvention = try c.decodeIfPresent(String.self, forKey: .loadConvention)
        ratio = try c.decodeIfPresent(Double.self, forKey: .ratio)
        tau = try c.decodeIfPresent(Double.self, forKey: .tau)
        ratioConfidence = try c.decodeIfPresent(String.self, forKey: .ratioConfidence)
        bwFraction = try c.decodeIfPresent(Double.self, forKey: .bwFraction)
        isCore = try c.decodeIfPresent(Bool.self, forKey: .isCore) ?? false
        isUnilateral = try c.decodeIfPresent(Bool.self, forKey: .isUnilateral) ?? false
        images = try c.decodeIfPresent([String].self, forKey: .images) ?? []
        translations = try c.decode([String: Translation].self, forKey: .translations)
        archived = try c.decodeIfPresent(Bool.self, forKey: .archived) ?? false
    }
}

/// The versioned catalog file (`catalog.v{N}.json`).
public struct CatalogPackage: Sendable, Equatable, Decodable {
    public var format: Int
    public var version: Int
    public var checksum: String
    public var exercises: [CatalogRecord]

    public init(format: Int = 1, version: Int, checksum: String, exercises: [CatalogRecord]) {
        self.format = format; self.version = version; self.checksum = checksum; self.exercises = exercises
    }

    /// The Swift side understands `format` 1; a newer file needs an app update.
    public static let supportedFormat = 1

    public static func decode(_ data: Data) throws -> CatalogPackage {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let package = try decoder.decode(CatalogPackage.self, from: data)
        guard package.format <= supportedFormat else { throw CatalogError.unsupportedFormat(package.format) }
        return package
    }
}

public struct CatalogVersionInfo: Sendable, Equatable {
    public var version: Int
    public var checksum: String
    /// Server timestamp string, exactly as PostgREST returned it (used as the change cursor).
    public var publishedAt: String

    public init(version: Int, checksum: String, publishedAt: String) {
        self.version = version; self.checksum = checksum; self.publishedAt = publishedAt
    }
}

public enum CatalogError: Error, Equatable {
    case unsupportedFormat(Int)
    case bundledCatalogMissing
    case invalidResponse(String)
}

public enum CatalogBootstrapResult: Sendable, Equatable {
    case upToDate(version: Int)
    /// First launch (or a newer bundled file after an app update): imported `count` exercises.
    case imported(version: Int, count: Int)
}

public enum CatalogSyncResult: Sendable, Equatable {
    case upToDate(version: Int)
    case updated(from: Int, to: Int, changed: Int)
    /// No catalog installed yet; `bootstrap()` has to run first.
    case notInstalled
}

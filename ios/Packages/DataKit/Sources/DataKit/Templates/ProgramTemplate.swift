import Foundation

// swiftlint:disable identifier_name
/// A text in both app languages. Template names and descriptions live in the template file, not in a String Catalog,
/// because they are data that ships (and is later updated) with the templates.
public struct TemplateText: Sendable, Equatable, Decodable {
    public let en: String
    public let tr: String

    public init(en: String, tr: String) {
        self.en = en
        self.tr = tr
    }

    /// `"tr"` gives Turkish, anything else English.
    public func resolve(languageCode: String) -> String { languageCode == "tr" ? tr : en }
}
// swiftlint:enable identifier_name

public enum TemplateLevel: String, Sendable, Codable, CaseIterable {
    case beginner, intermediate

    /// How well a lifter with this experience fits the level (0 = exactly, higher = worse).
    static func distance(from experience: Experience, to level: TemplateLevel) -> Int {
        let wanted: TemplateLevel
        switch experience {
        case .noExperience, .under6Months: wanted = .beginner
        case .sixMonthsToTwoYears, .twoToFiveYears, .over5Years: wanted = .intermediate
        }
        return wanted == level ? 0 : 1
    }
}

/// A ready-made program (P034): bundled JSON, never edited in place; choosing one creates an editable routine.
public struct ProgramTemplate: Sendable, Equatable, Identifiable, Decodable {
    public struct Exercise: Sendable, Equatable, Decodable {
        /// Catalog id (`exercises.id`).
        public let id: String
        public let sets: Int
        public let repsMin: Int
        public let repsMax: Int
        public let rir: Int
        public let restSeconds: Int

        public init(id: String, sets: Int, repsMin: Int, repsMax: Int, rir: Int = 2, restSeconds: Int = 90) {
            self.id = id
            self.sets = sets
            self.repsMin = repsMin
            self.repsMax = repsMax
            self.rir = rir
            self.restSeconds = restSeconds
        }
    }

    public struct Day: Sendable, Equatable, Decodable {
        public let name: TemplateText
        public let exercises: [Exercise]

        public init(name: TemplateText, exercises: [Exercise]) {
            self.name = name
            self.exercises = exercises
        }
    }

    public let id: String
    public let name: TemplateText
    public let audience: TemplateText
    public let summary: TemplateText
    public let level: TemplateLevel
    public let goals: [Goal]
    /// The least equipment access the template is written for.
    public let equipment: EquipmentAccess
    public let days: [Day]

    public init(
        id: String, name: TemplateText, audience: TemplateText, summary: TemplateText, level: TemplateLevel,
        goals: [Goal], equipment: EquipmentAccess, days: [Day]
    ) {
        self.id = id
        self.name = name
        self.audience = audience
        self.summary = summary
        self.level = level
        self.goals = goals
        self.equipment = equipment
        self.days = days
    }

    public var daysPerWeek: Int { days.count }
    public var exerciseCount: Int { days.reduce(0) { $0 + $1.exercises.count } }

    /// Time of each day in minutes: every set takes about 45 seconds plus its rest, plus five minutes of warm-up.
    public var minutesPerDay: [Int] {
        days.map { day in
            let seconds = day.exercises.reduce(0) { $0 + $1.sets * (Self.secondsPerSet + $1.restSeconds) }
            return Int((Double(seconds) / 60 + Self.warmupMinutes).rounded())
        }
    }

    /// The average session length, rounded to five minutes.
    public var estimatedMinutes: Int {
        guard !days.isEmpty else { return 0 }
        let average = Double(minutesPerDay.reduce(0, +)) / Double(days.count)
        return Int((average / 5).rounded()) * 5
    }

    static let secondsPerSet = 45
    static let warmupMinutes = 5.0
}

/// Weekly pushing and pulling sets of a template; a good program pulls about as much as it pushes.
public struct PushPullBalance: Sendable, Equatable {
    public let pushSets: Int
    public let pullSets: Int

    /// Pull sets per push set; `nil` when nothing is pushed.
    public var pullToPushRatio: Double? { pushSets == 0 ? nil : Double(pullSets) / Double(pushSets) }

    static let pushPatterns: Set<String> = ["horizontal_push", "vertical_push"]
    static let pullPatterns: Set<String> = ["horizontal_pull", "vertical_pull"]

    /// `pattern` maps a catalog id to its `movement_pattern`.
    public init(template: ProgramTemplate, pattern: (String) -> String?) {
        var push = 0, pull = 0
        for exercise in template.days.flatMap(\.exercises) {
            guard let found = pattern(exercise.id) else { continue }
            if Self.pushPatterns.contains(found) { push += exercise.sets }
            if Self.pullPatterns.contains(found) { pull += exercise.sets }
        }
        pushSets = push
        pullSets = pull
    }
}

/// The bundled `templates.v{N}.json`.
public struct TemplateLibrary: Sendable, Equatable, Decodable {
    public let format: Int
    public let version: Int
    public let templates: [ProgramTemplate]

    public static let supportedFormat = 1

    public init(format: Int = 1, version: Int, templates: [ProgramTemplate]) {
        self.format = format
        self.version = version
        self.templates = templates
    }

    public enum LoadError: Error, Equatable {
        case missingResource
        case unsupportedFormat(Int)
    }

    public static func decode(_ data: Data) throws -> TemplateLibrary {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let library = try decoder.decode(TemplateLibrary.self, from: data)
        guard library.format <= supportedFormat else { throw LoadError.unsupportedFormat(library.format) }
        return library
    }

    /// The templates that ship inside the DataKit package.
    public static func bundled() throws -> TemplateLibrary {
        guard let url = Bundle.module.url(forResource: "templates.v1", withExtension: "json") else {
            throw LoadError.missingResource
        }
        return try decode(Data(contentsOf: url))
    }

    public func template(id: String) -> ProgramTemplate? { templates.first { $0.id == id } }
}

import Foundation

/// Server side of the catalog sync: which version is current and which exercises changed since a point in time.
public protocol CatalogRemote: Sendable {
    func latestVersion() async throws -> CatalogVersionInfo?
    func version(_ number: Int) async throws -> CatalogVersionInfo?
    /// Exercises (with translations) whose `updated_at` is after `since`; archived ones carry `archived == true`.
    func changes(since: String) async throws -> [CatalogRecord]
}

/// PostgREST implementation using the anon key (the catalog tables are public read, docs/02-MIMARI.md §3).
public struct SupabaseCatalogRemote: CatalogRemote {
    public typealias Fetch = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    static let pageSize = 1000
    static let translationChunk = 40

    private let baseURL: URL
    private let anonKey: String
    private let fetch: Fetch

    public init(configuration: SupabaseConfiguration, session: URLSession = .shared) {
        self.init(baseURL: configuration.url, anonKey: configuration.anonKey) { try await session.data(for: $0) }
    }

    init(baseURL: URL, anonKey: String, fetch: @escaping Fetch) {
        self.baseURL = baseURL
        self.anonKey = anonKey
        self.fetch = fetch
    }

    public func latestVersion() async throws -> CatalogVersionInfo? {
        try await versions(query: "select=version,checksum,published_at&order=version.desc&limit=1").first
    }

    public func version(_ number: Int) async throws -> CatalogVersionInfo? {
        try await versions(query: "select=version,checksum,published_at&version=eq.\(number)").first
    }

    public func changes(since: String) async throws -> [CatalogRecord] {
        var rows: [ExerciseRow] = []
        while true {
            let query = "select=\(ExerciseRow.columns)&updated_at=gt.\(Self.encode(since))"
                + "&order=updated_at.asc,id.asc&limit=\(Self.pageSize)&offset=\(rows.count)"
            let page: [ExerciseRow] = try await get(table: "exercises", query: query)
            rows += page
            if page.count < Self.pageSize { break }
        }
        var translations: [String: [TranslationRow]] = [:]
        let ids = rows.map(\.id)
        for start in stride(from: 0, to: ids.count, by: Self.translationChunk) {
            let chunk = ids[start..<min(start + Self.translationChunk, ids.count)]
            let list = chunk.map { "\"\($0)\"" }.joined(separator: ",")
            let query = "select=exercise_id,locale,name,aliases,instructions&exercise_id=in.(\(Self.encode(list)))"
            let page: [TranslationRow] = try await get(table: "exercise_translations", query: query)
            for row in page { translations[row.exerciseId, default: []].append(row) }
        }
        return rows.map { $0.record(translations: translations[$0.id] ?? []) }
    }

    // MARK: - Plumbing

    private func versions(query: String) async throws -> [CatalogVersionInfo] {
        let rows: [VersionRow] = try await get(table: "catalog_versions", query: query)
        return rows.map { CatalogVersionInfo(version: $0.version, checksum: $0.checksum, publishedAt: $0.publishedAt) }
    }

    func request(table: String, query: String) throws -> URLRequest {
        guard let url = URL(string: baseURL.absoluteString + "/rest/v1/\(table)?\(query)") else {
            throw CatalogError.invalidResponse("bad URL for \(table)")
        }
        var request = URLRequest(url: url)
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(anonKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 30
        return request
    }

    private func get<T: Decodable>(table: String, query: String) async throws -> [T] {
        let (data, response) = try await fetch(try request(table: table, query: query))
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw CatalogError.invalidResponse("\(table): HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)")
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode([T].self, from: data)
    }

    /// Percent-encodes everything but unreserved characters (a raw `+` in a timestamp would read as a space).
    static func encode(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .unreserved) ?? value
    }

    // MARK: - Row types

    private struct VersionRow: Decodable {
        var version: Int
        var checksum: String
        var publishedAt: String
    }

    private struct TranslationRow: Decodable {
        var exerciseId: String
        var locale: String
        var name: String
        var aliases: [String]
        var instructions: [String]
    }

    private struct ExerciseRow: Decodable {
        static let columns = "id,equipment,mechanic,force,level,category,primary_muscles,secondary_muscles,"
            + "movement_pattern,scoring_type,anchor_lift,load_convention,ratio,tau,ratio_confidence,bw_fraction,"
            + "is_core,is_unilateral,image_paths,archived_at"

        var id: String
        var equipment: String?
        var mechanic: String?
        var force: String?
        var level: String
        var category: String
        var primaryMuscles: [String]
        var secondaryMuscles: [String]
        var movementPattern: String
        var scoringType: String
        var anchorLift: String?
        var loadConvention: String?
        var ratio: Double?
        var tau: Double?
        var ratioConfidence: String?
        var bwFraction: Double?
        var isCore: Bool
        var isUnilateral: Bool
        var imagePaths: [String]
        var archivedAt: String?

        func record(translations: [TranslationRow]) -> CatalogRecord {
            CatalogRecord(
                id: id, equipment: equipment, mechanic: mechanic, force: force, level: level, category: category,
                primaryMuscles: primaryMuscles, secondaryMuscles: secondaryMuscles, movementPattern: movementPattern,
                scoringType: scoringType, anchorLift: anchorLift, loadConvention: loadConvention, ratio: ratio,
                tau: tau, ratioConfidence: ratioConfidence, bwFraction: bwFraction, isCore: isCore,
                isUnilateral: isUnilateral, images: imagePaths,
                translations: Dictionary(uniqueKeysWithValues: translations.map {
                    ($0.locale, CatalogRecord.Translation(name: $0.name, aliases: $0.aliases, instructions: $0.instructions))
                }),
                archived: archivedAt != nil
            )
        }
    }
}

private extension CharacterSet {
    static let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
}

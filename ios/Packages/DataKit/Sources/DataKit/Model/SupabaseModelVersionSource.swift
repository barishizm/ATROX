import Foundation
import StrengthKit

/// `ModelVersionSource` over Supabase (P063): active rows of `public.model_versions` via PostgREST (anon key; the table is
/// public read) and bundle files from the public `model-bundles` bucket. Everything downloaded is verified by
/// `ModelUpdater` (signature, digests, smoke test) before use.
public struct SupabaseModelVersionSource: ModelVersionSource {
    public typealias Fetch = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    static let columns = "version,schema_version,min_app_version,storage_path,manifest_sha256,is_active,rollout_percent"

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

    public func activeVersions() async throws -> [ModelVersionRecord] {
        let data = try await get("/rest/v1/model_versions?select=\(Self.columns)&is_active=eq.true")
        return try JSONDecoder().decode([ModelVersionRecord].self, from: data)
    }

    public func download(_ path: String) async throws -> Data {
        try await get("/storage/v1/object/public/model-bundles/\(path)")
    }

    private func get(_ path: String) async throws -> Data {
        guard let url = URL(string: baseURL.absoluteString + path) else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(anonKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 30
        let (data, response) = try await fetch(request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return data
    }
}

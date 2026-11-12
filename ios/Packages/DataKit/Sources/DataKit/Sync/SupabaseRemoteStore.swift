import Foundation

/// `RemoteStore` over PostgREST, acting as the signed-in user (RLS limits every call to their rows).
public struct SupabaseRemoteStore: RemoteStore {
    public typealias Fetch = @Sendable (URLRequest) async throws -> (Data, URLResponse)
    /// The user's current access token (refreshed by the auth SDK); nil when signed out.
    public typealias AccessToken = @Sendable () async -> String?

    private let baseURL: URL
    private let anonKey: String
    private let accessToken: AccessToken
    private let fetch: Fetch

    public init(configuration: SupabaseConfiguration, accessToken: @escaping AccessToken, session: URLSession = .shared) {
        self.init(baseURL: configuration.url, anonKey: configuration.anonKey, accessToken: accessToken) {
            try await session.data(for: $0)
        }
    }

    init(baseURL: URL, anonKey: String, accessToken: @escaping AccessToken, fetch: @escaping Fetch) {
        self.baseURL = baseURL
        self.anonKey = anonKey
        self.accessToken = accessToken
        self.fetch = fetch
    }

    public func upsert(table: SyncTable, rows: [JSONObject]) async throws -> [JSONObject] {
        guard !rows.isEmpty else { return [] }
        var request = try await request(path: table.rawValue, query: "on_conflict=id", method: "POST")
        request.setValue("resolution=merge-duplicates,return=representation", forHTTPHeaderField: "Prefer")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(rows)
        let (data, _) = try await send(request)
        return try decodeRows(data)
    }

    public func changes(table: SyncTable, after cursor: SyncCursor?, limit: Int) async throws -> [JSONObject] {
        let query = "select=*" + Self.filter(after: cursor) + "&order=updated_at.asc,id.asc&limit=\(limit)"
        let (data, _) = try await send(try await request(path: table.rawValue, query: query, method: "GET"))
        return try decodeRows(data)
    }

    public func countChanges(table: SyncTable, after cursor: SyncCursor?) async throws -> Int {
        var request = try await request(path: table.rawValue, query: "select=id" + Self.filter(after: cursor) + "&limit=1", method: "GET")
        request.setValue("count=exact", forHTTPHeaderField: "Prefer")
        let (_, response) = try await send(request)
        // Content-Range: "0-0/123" or "*/0".
        let range = response.value(forHTTPHeaderField: "Content-Range") ?? ""
        return range.split(separator: "/").last.flatMap { Int($0) } ?? 0
    }

    public func serverTime() async throws -> Date {
        var request = try await request(path: "rpc/server_time", query: "", method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data("{}".utf8)
        let (data, _) = try await send(request)
        guard let text = try? JSONDecoder().decode(String.self, from: data), let date = SyncTime.parseTimestamp(text) else {
            throw RemoteStoreError.transient("server_time: unreadable answer")
        }
        return date
    }

    // MARK: Plumbing

    /// Keyset condition `(updated_at, id) > cursor`; values are quoted because timestamps contain `.` and `:`.
    static func filter(after cursor: SyncCursor?) -> String {
        guard let cursor else { return "" }
        let stamp = cursor.updatedAt
        let id = cursor.id.uuidString.lowercased()
        let condition = "(updated_at.gt.\"\(stamp)\",and(updated_at.eq.\"\(stamp)\",id.gt.\(id)))"
        return "&or=" + SupabaseCatalogRemote.encode(condition)
    }

    private func request(path: String, query: String, method: String) async throws -> URLRequest {
        guard let token = await accessToken() else { throw RemoteStoreError.unauthorized }
        let suffix = query.isEmpty ? "" : "?\(query)"
        guard let url = URL(string: baseURL.absoluteString + "/rest/v1/\(path)\(suffix)") else {
            throw RemoteStoreError.permanent("bad URL for \(path)")
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 30
        return request
    }

    private func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await fetch(request)
        } catch {
            throw RemoteStoreError.transient(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else { throw RemoteStoreError.transient("no HTTP response") }
        guard (200..<300).contains(http.statusCode) else { throw Self.error(status: http.statusCode, body: data) }
        return (data, http)
    }

    /// PostgREST error → transient (retry later) or permanent (the data is wrong).
    static func error(status: Int, body: Data) -> RemoteStoreError {
        let payload = (try? JSONDecoder().decode([String: JSONValue].self, from: body)) ?? [:]
        let code = payload["code"]?.stringValue ?? ""
        let message = payload["message"]?.stringValue ?? "HTTP \(status)"
        if status == 401 || code == "PGRST301" || code == "PGRST302" { return .unauthorized }
        if status == 408 || status == 429 || status >= 500 { return .transient("\(code) \(message)") }
        return .permanent([code, message].filter { !$0.isEmpty }.joined(separator: " "))
    }

    private func decodeRows(_ data: Data) throws -> [JSONObject] {
        do {
            return try JSONDecoder().decode([JSONObject].self, from: data)
        } catch {
            throw RemoteStoreError.transient("unreadable rows: \(error.localizedDescription)")
        }
    }
}

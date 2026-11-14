import Foundation

/// `CoachRemote` over PostgREST with the user's session token (RLS keeps every row the caller's own).
public struct SupabaseCoachRemote: CoachRemote {
    public typealias Fetch = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    private let baseURL: URL
    private let anonKey: String
    private let accessToken: @Sendable () async -> String?
    private let fetch: Fetch

    public init(
        baseURL: URL, anonKey: String, accessToken: @escaping @Sendable () async -> String?, session: URLSession = .shared
    ) {
        self.init(baseURL: baseURL, anonKey: anonKey, accessToken: accessToken) { try await session.data(for: $0) }
    }

    init(baseURL: URL, anonKey: String, accessToken: @escaping @Sendable () async -> String?, fetch: @escaping Fetch) {
        self.baseURL = baseURL
        self.anonKey = anonKey
        self.accessToken = accessToken
        self.fetch = fetch
    }

    public func threads(limit: Int, before: Date?) async throws -> [CoachThread] {
        var query = [
            URLQueryItem(name: "select", value: "id,title,created_at,updated_at"),
            URLQueryItem(name: "deleted_at", value: "is.null"),
            URLQueryItem(name: "order", value: "updated_at.desc"),
            URLQueryItem(name: "limit", value: String(limit))
        ]
        if let before { query.append(URLQueryItem(name: "updated_at", value: "lt.\(CoachDates.format(before))")) }
        let rows = try await get("coach_threads", query)
        return rows.compactMap { row in
            guard let id = row["id"]?.string.flatMap(UUID.init(uuidString:)), let created = Self.date(row["created_at"]),
                  let updated = Self.date(row["updated_at"]) else { return nil }
            return CoachThread(id: id, title: row["title"]?.string, createdAt: created, updatedAt: updated)
        }
    }

    public func messages(threadId: UUID, limit: Int, before: Date?) async throws -> [CoachStoredMessage] {
        var query = [
            URLQueryItem(name: "select", value: "id,role,content,proposal,status,created_at"),
            URLQueryItem(name: "thread_id", value: "eq.\(threadId.uuidString.lowercased())"),
            URLQueryItem(name: "deleted_at", value: "is.null"),
            URLQueryItem(name: "order", value: "created_at.desc"),
            URLQueryItem(name: "limit", value: String(limit))
        ]
        if let before { query.append(URLQueryItem(name: "created_at", value: "lt.\(CoachDates.format(before))")) }
        let rows = try await get("coach_messages", query)
        return rows.compactMap { row in
            guard let id = row["id"]?.string.flatMap(UUID.init(uuidString:)), let role = row["role"]?.string,
                  let created = Self.date(row["created_at"]) else { return nil }
            let proposal = row["proposal"].flatMap { value -> CoachProposal? in
                guard case .object = value, let data = try? JSONEncoder().encode(value) else { return nil }
                return try? JSONDecoder().decode(CoachProposal.self, from: data)
            }
            return CoachStoredMessage(
                id: id, role: role, content: row["content"]?.string ?? "", proposal: proposal,
                status: row["status"]?.string ?? "complete", createdAt: created
            )
        }
    }

    public func renameThread(id: UUID, title: String) async throws {
        try await send("PATCH", "coach_threads", query: [URLQueryItem(name: "id", value: "eq.\(id.uuidString.lowercased())")], body: ["title": title])
    }

    public func deleteThread(id: UUID) async throws { try await rpc("coach_delete_thread", ["p_id": id.uuidString.lowercased()]) }

    public func deleteAllThreads() async throws { try await rpc("coach_delete_all_threads", [:]) }

    public func memory() async throws -> [CoachMemoryNote] {
        let rows = try await get("coach_memory", [
            URLQueryItem(name: "select", value: "id,note,source,created_at"),
            URLQueryItem(name: "deleted_at", value: "is.null"),
            URLQueryItem(name: "order", value: "created_at.asc")
        ])
        return rows.compactMap { row in
            guard let id = row["id"]?.string.flatMap(UUID.init(uuidString:)), let note = row["note"]?.string,
                  let created = Self.date(row["created_at"]) else { return nil }
            return CoachMemoryNote(id: id, note: note, source: row["source"]?.string ?? "coach", createdAt: created)
        }
    }

    public func editMemory(id: UUID, note: String) async throws {
        try await rpc("coach_edit_memory", ["p_id": id.uuidString.lowercased(), "p_note": note])
    }

    public func deleteMemory(id: UUID) async throws { try await rpc("coach_delete_memory", ["p_id": id.uuidString.lowercased()]) }

    public func recordDecision(proposalID: String, decision: CoachProposal.Decision) async throws {
        try await rpc("coach_record_decision", ["p_proposal_id": proposalID, "p_decision": decision.rawValue])
    }

    // MARK: HTTP

    private static func date(_ value: CoachJSON?) -> Date? { value?.string.flatMap(CoachDates.parse) }

    private func get(_ table: String, _ query: [URLQueryItem]) async throws -> [CoachJSON] {
        let data = try await perform(request("GET", "rest/v1/\(table)", query: query, body: nil))
        return (try? JSONDecoder().decode([CoachJSON].self, from: data)) ?? []
    }

    private func send(_ method: String, _ table: String, query: [URLQueryItem], body: [String: String]) async throws {
        _ = try await perform(request(method, "rest/v1/\(table)", query: query, body: JSONEncoder().encode(body)))
    }

    private func rpc(_ function: String, _ arguments: [String: String]) async throws {
        _ = try await perform(request("POST", "rest/v1/rpc/\(function)", query: [], body: JSONEncoder().encode(arguments)))
    }

    private func request(_ method: String, _ path: String, query: [URLQueryItem], body: Data?) async throws -> URLRequest {
        guard let token = await accessToken() else { throw CoachError.unauthorized }
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        if !query.isEmpty { components?.queryItems = query }
        guard let url = components?.url else { throw CoachError.invalidResponse }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 30
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        return request
    }

    private func perform(_ request: URLRequest) async throws -> Data {
        do {
            let (data, response) = try await fetch(request)
            guard let http = response as? HTTPURLResponse else { throw CoachError.invalidResponse }
            guard (200..<300).contains(http.statusCode) else { throw CoachError.from(status: http.statusCode, body: data) }
            return data
        } catch {
            throw CoachError.from(error)
        }
    }
}

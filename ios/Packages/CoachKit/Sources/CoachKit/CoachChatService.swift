import Foundation

/// What the app sends for one turn.
public struct CoachChatRequest: Sendable, Equatable {
    public var threadId: UUID?
    /// Also the id of the stored user message: a retry sends the same id, so the server never stores it twice.
    public let clientMessageId: UUID
    public let message: String
    public let locale: String
    public let timeZone: String

    public init(threadId: UUID?, clientMessageId: UUID, message: String, locale: String, timeZone: String) {
        self.threadId = threadId
        self.clientMessageId = clientMessageId
        self.message = message
        self.locale = locale
        self.timeZone = timeZone
    }

    var jsonBody: Data {
        var body: [String: String] = [
            "client_message_id": clientMessageId.uuidString.lowercased(), "message": message, "locale": locale,
            "time_zone": timeZone
        ]
        if let threadId { body["thread_id"] = threadId.uuidString.lowercased() }
        return (try? JSONEncoder().encode(body)) ?? Data()
    }
}

/// One coach turn as a stream of events. Finishes with the last event, or throws a `CoachError`.
public protocol CoachChatService: Sendable {
    func stream(_ request: CoachChatRequest) -> AsyncThrowingStream<CoachEvent, any Error>
}

/// `coach-chat` Edge Function over SSE, authorised with the Supabase session token. A 401 refreshes the token and
/// tries once more (only before any event was delivered).
public struct SupabaseCoachChatService: CoachChatService {
    public typealias Token = @Sendable () async -> String?

    private let baseURL: URL
    private let anonKey: String
    private let accessToken: Token
    private let refreshedToken: Token
    private let client: SSEClient

    public init(baseURL: URL, anonKey: String, accessToken: @escaping Token, refreshedToken: @escaping Token, client: SSEClient = SSEClient()) {
        self.baseURL = baseURL
        self.anonKey = anonKey
        self.accessToken = accessToken
        self.refreshedToken = refreshedToken
        self.client = client
    }

    public func stream(_ chatRequest: CoachChatRequest) -> AsyncThrowingStream<CoachEvent, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await run(chatRequest, continuation: continuation)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: CoachError.from(error))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func run(_ chatRequest: CoachChatRequest, continuation: AsyncThrowingStream<CoachEvent, any Error>.Continuation) async throws {
        var token = await accessToken()
        for attempt in 0..<2 {
            guard let current = token else { throw CoachError.unauthorized }
            var delivered = false
            do {
                for try await frame in client.frames(for: makeRequest(chatRequest, token: current)) {
                    delivered = true
                    if let event = CoachEvent.decode(frame) { continuation.yield(event) }
                }
                return
            } catch CoachError.unauthorized where attempt == 0 && !delivered {
                token = await refreshedToken()
            }
        }
        throw CoachError.unauthorized
    }

    func makeRequest(_ chatRequest: CoachChatRequest, token: String) -> URLRequest {
        var request = URLRequest(url: baseURL.appendingPathComponent("functions/v1/coach-chat"))
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.httpBody = chatRequest.jsonBody
        return request
    }
}

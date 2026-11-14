import Foundation
@testable import CoachKit

/// Replays recorded responses; each `open` pops the next one.
final class FakeTransport: CoachTransport, @unchecked Sendable {
    struct Reply {
        var status = 200
        var chunks: [Data] = []
        /// Error thrown after the chunks (a dropped connection).
        var failure: (any Error)?
        /// Keep the stream open after the chunks, like a stalled server.
        var hang = false
    }

    private let lock = NSLock()
    private var replies: [Reply]
    private(set) var requests: [URLRequest] = []

    init(_ replies: [Reply]) {
        self.replies = replies
    }

    func open(_ request: URLRequest) async throws -> (HTTPURLResponse, AsyncThrowingStream<Data, any Error>) {
        let reply = lock.withLock { () -> Reply in
            requests.append(request)
            return replies.isEmpty ? Reply(status: 500) : replies.removeFirst()
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: reply.status, httpVersion: nil, headerFields: nil)!
        let stream = AsyncThrowingStream<Data, any Error> { continuation in
            for chunk in reply.chunks { continuation.yield(chunk) }
            if let failure = reply.failure {
                continuation.finish(throwing: failure)
            } else if !reply.hang {
                continuation.finish()
            }
        }
        return (response, stream)
    }

    static func ok(_ text: String, chunk: Int = 9) -> Reply {
        let bytes = Array(text.utf8)
        let chunks = stride(from: 0, to: bytes.count, by: chunk).map { Data(bytes[$0..<min($0 + chunk, bytes.count)]) }
        return Reply(chunks: chunks)
    }

    static func error(_ status: Int, code: String, details: String = "null") -> Reply {
        Reply(status: status, chunks: [Data(#"{"error":{"code":"\#(code)","message":"m","details":\#(details)}}"#.utf8)])
    }
}

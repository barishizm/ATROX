import Foundation

/// Opens an HTTP request and hands back the response head plus the body as it arrives. The app uses URLSession; tests
/// replay recorded streams.
public protocol CoachTransport: Sendable {
    func open(_ request: URLRequest) async throws -> (HTTPURLResponse, AsyncThrowingStream<Data, any Error>)
}

/// URLSession bytes, regrouped into complete lines so a frame is delivered the moment its blank line arrives.
public struct URLSessionCoachTransport: CoachTransport {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func open(_ request: URLRequest) async throws -> (HTTPURLResponse, AsyncThrowingStream<Data, any Error>) {
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else { throw CoachError.invalidResponse }
        let stream = AsyncThrowingStream<Data, any Error> { continuation in
            let task = Task {
                do {
                    var line = Data()
                    for try await byte in bytes {
                        line.append(byte)
                        if byte == 0x0A {
                            continuation.yield(line)
                            line.removeAll(keepingCapacity: true)
                        }
                    }
                    if !line.isEmpty { continuation.yield(line) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
        return (http, stream)
    }
}

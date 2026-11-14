import Foundation

/// Reads a server-sent event stream: maps HTTP errors to `CoachError`, parses frames and watches for a stalled
/// connection (no bytes for `idleTimeout`; the server sends a frame at least every few seconds while it works).
public struct SSEClient: Sendable {
    private let transport: any CoachTransport
    private let idleTimeout: Duration

    public init(transport: any CoachTransport = URLSessionCoachTransport(), idleTimeout: Duration = .seconds(45)) {
        self.transport = transport
        self.idleTimeout = idleTimeout
    }

    public func frames(for request: URLRequest) -> AsyncThrowingStream<SSEFrame, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await run(request, continuation: continuation)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: CoachError.from(error))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func run(_ request: URLRequest, continuation: AsyncThrowingStream<SSEFrame, any Error>.Continuation) async throws {
        let (response, chunks) = try await transport.open(request)
        guard (200..<300).contains(response.statusCode) else {
            var body = Data()
            for try await chunk in chunks { body.append(chunk) }
            throw CoachError.from(status: response.statusCode, body: body)
        }
        let watchdog = IdleWatchdog()
        let timeout = idleTimeout
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                var parser = SSEParser()
                for try await chunk in chunks {
                    await watchdog.touch()
                    for frame in parser.feed(chunk) { continuation.yield(frame) }
                }
            }
            group.addTask {
                while true {
                    try await Task.sleep(for: .milliseconds(500))
                    if await watchdog.idleFor() > timeout { throw CoachError.timeout }
                }
            }
            defer { group.cancelAll() }
            try await group.next()
        }
    }
}

private actor IdleWatchdog {
    private var last = ContinuousClock.now

    func touch() {
        last = .now
    }

    func idleFor() -> Duration {
        .now - last
    }
}

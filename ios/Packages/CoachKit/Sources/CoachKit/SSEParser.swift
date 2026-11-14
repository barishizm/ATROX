import Foundation

/// One dispatched server-sent event.
public struct SSEFrame: Sendable, Equatable {
    public let event: String
    public let data: String

    public init(event: String, data: String) {
        self.event = event
        self.data = data
    }
}

/// Incremental parser for `text/event-stream`. Feed it whatever chunks arrive; lines may be split anywhere (also in the
/// middle of a multi-byte character). Handles `\n` and `\r\n`, comment lines and multi-line `data:` fields.
public struct SSEParser: Sendable {
    private var buffer = Data()
    private var event: String?
    private var dataLines: [String] = []

    public init() {}

    public mutating func feed(_ chunk: Data) -> [SSEFrame] {
        buffer.append(chunk)
        var frames: [SSEFrame] = []
        while let newline = buffer.firstIndex(of: 0x0A) {
            var line = buffer[buffer.startIndex..<newline]
            buffer = Data(buffer[buffer.index(after: newline)...])
            if line.last == 0x0D { line = line.dropLast() }
            if let frame = consume(String(decoding: line, as: UTF8.self)) { frames.append(frame) }
        }
        return frames
    }

    private mutating func consume(_ line: String) -> SSEFrame? {
        if line.isEmpty {
            defer {
                event = nil
                dataLines = []
            }
            guard !dataLines.isEmpty else { return nil }
            return SSEFrame(event: event ?? "message", data: dataLines.joined(separator: "\n"))
        }
        if line.hasPrefix(":") { return nil }
        let name: Substring
        var value: Substring = ""
        if let colon = line.firstIndex(of: ":") {
            name = line[..<colon]
            value = line[line.index(after: colon)...]
            if value.first == " " { value = value.dropFirst() }
        } else {
            name = Substring(line)
        }
        switch name {
        case "event": event = String(value)
        case "data": dataLines.append(String(value))
        default: break  // id, retry and unknown fields are not used
        }
        return nil
    }
}

import Foundation

/// A JSON value that is `Sendable`: the wire format between the sync engine and a `RemoteStore` (PostgREST rows).
public enum JSONValue: Sendable, Hashable, Codable {
    case null
    case bool(Bool)
    case int(Int)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .int(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }

    public var stringValue: String? {
        if case .string(let value) = self { value } else { nil }
    }

    public var isNull: Bool { self == .null }
}

/// One table row as PostgREST sends and receives it (snake_case keys).
public typealias JSONObject = [String: JSONValue]

extension JSONObject {
    var rowId: UUID? { self["id"]?.stringValue.flatMap(UUID.init(uuidString:)) }
    var rowUserId: UUID? { self["user_id"]?.stringValue.flatMap(UUID.init(uuidString:)) }
    var rowUpdatedAt: String? { self["updated_at"]?.stringValue }
}

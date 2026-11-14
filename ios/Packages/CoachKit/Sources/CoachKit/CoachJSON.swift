import Foundation

/// Arbitrary JSON, used for proposal payloads whose shape depends on the proposal kind.
public enum CoachJSON: Sendable, Equatable, Codable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([CoachJSON])
    case object([String: CoachJSON])

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([CoachJSON].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: CoachJSON].self))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }

    public subscript(key: String) -> CoachJSON? {
        if case .object(let object) = self { object[key] } else { nil }
    }

    public var string: String? {
        if case .string(let value) = self { value } else { nil }
    }

    public var double: Double? {
        if case .number(let value) = self { value } else { nil }
    }

    public var int: Int? { double.flatMap { $0.rounded() == $0 ? Int($0) : nil } }

    public var array: [CoachJSON]? {
        if case .array(let value) = self { value } else { nil }
    }
}

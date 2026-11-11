import Foundation

/// Placeholder chat message model; the full message/tool-event model arrives in the coach steps.
public struct CoachMessage: Sendable, Codable, Equatable, Identifiable {
    public enum Role: String, Sendable, Codable {
        case user
        case assistant
    }

    public let id: UUID
    public let role: Role
    public let text: String

    public init(id: UUID = UUID(), role: Role, text: String) {
        self.id = id
        self.role = role
        self.text = text
    }
}

import Foundation

/// One bubble of a conversation: what the user wrote or what the coach answered, plus the cards the coach attached.
public struct CoachMessage: Sendable, Codable, Equatable, Identifiable {
    public enum Role: String, Sendable, Codable {
        case user
        case assistant
    }

    public enum Status: String, Sendable, Codable {
        case complete
        /// Text is still arriving.
        case streaming
        /// The turn was cut off (stopped by the user, or the connection dropped); the text so far is kept.
        case partial
    }

    public let id: UUID
    public let role: Role
    public var text: String
    public var status: Status
    public var proposals: [CoachProposal]
    public let createdAt: Date

    public init(
        id: UUID = UUID(), role: Role, text: String, status: Status = .complete, proposals: [CoachProposal] = [],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.status = status
        self.proposals = proposals
        self.createdAt = createdAt
    }

    enum CodingKeys: String, CodingKey { case id, role, text, status, proposals, createdAt }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        role = try container.decode(Role.self, forKey: .role)
        text = try container.decode(String.self, forKey: .text)
        status = try container.decodeIfPresent(Status.self, forKey: .status) ?? .complete
        proposals = try container.decodeIfPresent([CoachProposal].self, forKey: .proposals) ?? []
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
    }
}

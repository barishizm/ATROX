import Foundation

public struct CoachThread: Sendable, Codable, Equatable, Identifiable {
    public let id: UUID
    public var title: String?
    public let createdAt: Date
    public var updatedAt: Date

    public init(id: UUID, title: String?, createdAt: Date, updatedAt: Date) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// A note the coach keeps about the user (at most 20; the user edits and deletes them).
public struct CoachMemoryNote: Sendable, Codable, Equatable, Identifiable {
    public let id: UUID
    public var note: String
    /// `coach` (saved by the coach) or `user` (written or edited by the user).
    public let source: String
    public let createdAt: Date

    public init(id: UUID, note: String, source: String, createdAt: Date) {
        self.id = id
        self.note = note
        self.source = source
        self.createdAt = createdAt
    }
}

/// A `coach_messages` row as the server stores it (tool rows carry the proposals).
public struct CoachStoredMessage: Sendable, Equatable {
    public let id: UUID
    public let role: String
    public let content: String
    public let proposal: CoachProposal?
    public let status: String
    public let createdAt: Date

    public init(id: UUID, role: String, content: String, proposal: CoachProposal?, status: String = "complete", createdAt: Date) {
        self.id = id
        self.role = role
        self.content = content
        self.proposal = proposal
        self.status = status
        self.createdAt = createdAt
    }
}

public enum CoachHistory {
    /// Turns stored rows (oldest first) into chat bubbles. A proposal stored on a tool row belongs to the answer that
    /// follows it; tool rows and assistant rows without text (pure tool calls) produce no bubble of their own.
    public static func messages(from rows: [CoachStoredMessage]) -> [CoachMessage] {
        var result: [CoachMessage] = []
        var pending: [CoachProposal] = []
        for row in rows.sorted(by: { $0.createdAt < $1.createdAt }) {
            switch row.role {
            case "user":
                pending = []
                result.append(CoachMessage(id: row.id, role: .user, text: row.content, createdAt: row.createdAt))
            case "tool":
                if let proposal = row.proposal { pending.append(proposal) }
            case "assistant":
                guard !row.content.isEmpty || !pending.isEmpty else { continue }
                result.append(CoachMessage(
                    id: row.id, role: .assistant, text: row.content, status: row.status == "partial" ? .partial : .complete,
                    proposals: pending, createdAt: row.createdAt
                ))
                pending = []
            default:
                continue
            }
        }
        if !pending.isEmpty, let last = result.indices.last, result[last].role == .assistant { result[last].proposals += pending }
        return result
    }
}

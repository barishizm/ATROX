import Foundation

/// A change the coach suggests (docs/04-AI-KOC.md §5). The coach never changes data itself: the app shows a card and
/// the user decides. `memory_saved` is already stored; its card only lets the user undo it.
public struct CoachProposal: Sendable, Equatable, Identifiable, Codable {
    public enum Kind: String, Sendable, Codable {
        case routine
        case routineEdit = "routine_edit"
        case exerciseSwap = "exercise_swap"
        case goalUpdate = "goal_update"
        case memorySaved = "memory_saved"
        /// A kind a newer server knows and this app does not: shown as an unsupported card (forward compatibility).
        case unknown
    }

    public enum Decision: String, Sendable, Codable {
        case applied, edited, rejected, undone
    }

    public struct Warning: Sendable, Equatable, Codable {
        public let exerciseId: String
        public let area: String

        public init(exerciseId: String, area: String) {
            self.exerciseId = exerciseId
            self.area = area
        }

        enum CodingKeys: String, CodingKey {
            case exerciseId = "exercise_id"
            case area
        }
    }

    public let id: String
    public let kind: Kind
    public let data: CoachJSON
    public let warnings: [Warning]
    public var decision: Decision?

    public init(id: String, kind: Kind, data: CoachJSON = .null, warnings: [Warning] = [], decision: Decision? = nil) {
        self.id = id
        self.kind = kind
        self.data = data
        self.warnings = warnings
        self.decision = decision
    }

    enum CodingKeys: String, CodingKey { case id, kind, data, warnings, decision }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        kind = (try? container.decode(Kind.self, forKey: .kind)) ?? .unknown
        data = try container.decodeIfPresent(CoachJSON.self, forKey: .data) ?? .null
        warnings = try container.decodeIfPresent([Warning].self, forKey: .warnings) ?? []
        decision = (try? container.decodeIfPresent(Decision.self, forKey: .decision)) ?? nil
    }

    /// Needs the user's answer: everything except the note that is already saved.
    public var needsDecision: Bool { kind != .memorySaved && decision == nil }
}

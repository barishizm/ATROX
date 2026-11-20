import Foundation

/// What a diary log row records. The meaning of `amount` and `quantity` depends on the kind:
///
/// | kind        | amount          | quantity        | label        | text      |
/// |-------------|-----------------|-----------------|--------------|-----------|
/// | water       | millilitres     |                 |              |           |
/// | activity    | kcal burned     | minutes         | activity     |           |
/// | steps       | kcal burned     | steps           |              |           |
/// | note        |                 |                 | mood         | the note  |
/// | fast        |                 | planned hours   | plan name    | (`endedAt` is when it ended)  |
/// | goalWeight  | kilograms       |                 |              |           |
public enum DiaryLogKind: String, Sendable, Codable, CaseIterable {
    case water, activity, steps, note, fast
    case goalWeight = "goal_weight"
}

public struct DiaryLogInput: Sendable, Equatable {
    public var kind: DiaryLogKind
    public var at: Date
    public var endedAt: Date?
    public var amount: Double
    public var quantity: Double
    public var label: String
    public var text: String

    public init(
        kind: DiaryLogKind, at: Date, endedAt: Date? = nil, amount: Double = 0, quantity: Double = 0, label: String = "", text: String = ""
    ) {
        self.kind = kind
        self.at = at
        self.endedAt = endedAt
        self.amount = amount
        self.quantity = quantity
        self.label = label
        self.text = text
    }
}

public struct DiaryLogSnapshot: Sendable, Equatable, Identifiable {
    public let id: UUID
    public let userId: UUID
    public let createdAt: Date
    public let updatedAt: Date
    public let syncState: SyncState
    public let input: DiaryLogInput

    public init(id: UUID = UUID(), userId: UUID, createdAt: Date = Date(), updatedAt: Date? = nil, syncState: SyncState = .pending, input: DiaryLogInput) {
        self.id = id
        self.userId = userId
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
        self.syncState = syncState
        self.input = input
    }
}

/// The ranges the server enforces too (`diary_logs` check constraints).
public enum DiaryLogLimits {
    public static func isValid(_ input: DiaryLogInput) -> Bool {
        guard (0...10_000).contains(input.amount), (0...100_000).contains(input.quantity),
              input.label.count <= 80, input.text.count <= 2000 else { return false }
        switch input.kind {
        case .water: return input.amount > 0 && input.amount <= 5000
        case .activity: return !input.label.isEmpty && input.quantity > 0
        case .steps: return input.quantity > 0
        case .note: return !input.label.isEmpty || !input.text.isEmpty
        case .fast: return input.quantity > 0 && (input.endedAt.map { $0 >= input.at } ?? true)
        case .goalWeight: return (20...400).contains(input.amount)
        }
    }
}

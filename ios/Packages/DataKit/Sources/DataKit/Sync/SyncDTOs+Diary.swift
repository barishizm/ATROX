import Foundation
import SwiftData

public struct DiaryLogDTO: SyncDTO {
    public var id: UUID
    public var userId: UUID
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?
    public var kind: String
    public var at: Date
    public var endedAt: Date?
    public var amount: Double
    public var quantity: Double
    public var label: String
    public var text: String
}

extension DiaryLog: SyncableModel {
    public static var syncTable: SyncTable { .diaryLogs }

    public func makeDTO() -> DiaryLogDTO {
        DiaryLogDTO(
            id: id, userId: userId, createdAt: createdAt, updatedAt: updatedAt, deletedAt: deletedAt, kind: kindRaw, at: at,
            endedAt: endedAt, amount: amount, quantity: quantity, label: label, text: text
        )
    }

    public func apply(_ dto: DiaryLogDTO) {
        applyCommon(dto)
        kindRaw = dto.kind
        at = dto.at
        endedAt = dto.endedAt
        amount = dto.amount
        quantity = dto.quantity
        label = dto.label
        text = dto.text
    }

    public convenience init(syncDTO dto: DiaryLogDTO) {
        self.init(userId: dto.userId, input: DiaryLogInput(kind: .note, at: dto.at), now: dto.createdAt)
        id = dto.id
        apply(dto)
    }
}

extension DiaryLog {
    public static func syncDescriptor(_ filter: SyncFilter) -> FetchDescriptor<DiaryLog> {
        switch filter {
        case .state(let state, let userId):
            let raw = state.rawValue
            return FetchDescriptor(predicate: #Predicate<DiaryLog> { $0.userId == userId && $0.syncStateRaw == raw })
        case .id(let id):
            var descriptor = FetchDescriptor(predicate: #Predicate<DiaryLog> { $0.id == id })
            descriptor.fetchLimit = 1
            return descriptor
        case .user(let userId):
            return FetchDescriptor(predicate: #Predicate<DiaryLog> { $0.userId == userId })
        case .all:
            return FetchDescriptor()
        }
    }
}

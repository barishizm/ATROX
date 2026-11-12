import DataKit
import Foundation

/// Personal-record display state of the active workout (P040).
extension ActiveWorkoutModel {
    // MARK: Records

    /// Shows the best record a just-completed set broke. A suspicious e1RM jump asks first and shows nothing until
    /// the user confirms it.
    func show(_ hits: [PersonalRecordHit], for setId: UUID) {
        recordHits.append(contentsOf: hits)
        guard let top = hits.min(by: { Self.rank($0.kind) < Self.rank($1.kind) }), let input = session.set(setId)?.input else { return }
        if hits.contains(where: \.needsConfirmation) {
            recordToConfirm = hits.first(where: \.needsConfirmation)
            return
        }
        celebrate(top.kind, setId: setId, input: input)
    }

    /// "Yes, it's right": the held-back record is shown after all.
    func confirmRecord() {
        guard let hit = recordToConfirm, let input = session.set(hit.setId)?.input else { recordToConfirm = nil; return }
        recordToConfirm = nil
        recordHits.append(
            PersonalRecordHit(
                ref: hit.ref, kind: hit.kind, value: hit.value, setId: hit.setId, previousValue: hit.previousValue
            )
        )
        celebrate(.e1rm, setId: hit.setId, input: input)
    }

    /// "No, fix it": opens the weight of the suspicious set in the keypad.
    func reviseRecordSet() async {
        guard let hit = recordToConfirm else { return }
        recordToConfirm = nil
        await beginEditing(hit.setId, field: .weight)
    }

    func celebrate(_ kind: RecordKind, setId: UUID, input: SetInput) {
        recordBadges[setId] = RecordBadge(kind: kind, input: input)
        recordCelebrations += 1
    }

    static func rank(_ kind: RecordKind) -> Int {
        switch kind {
        case .weight: 0
        case .e1rm: 1
        case .volume: 2
        case .reps: 3
        }
    }

    func recordBadge(for entry: SetSnapshot) -> RecordKind? {
        guard let badge = recordBadges[entry.id], badge.input == entry.input else { return nil }
        return badge.kind
    }
}

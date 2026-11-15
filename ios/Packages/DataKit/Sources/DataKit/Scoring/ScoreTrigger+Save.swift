import Foundation
import SwiftData

extension ScoreTrigger {
    /// Entities the score refresh itself writes (and nothing score-relevant reads): saves that touch only these cannot
    /// change a score, so they must not start another refresh.
    private static let derivedEntities: Set<String> = [
        String(describing: ScoreSnapshot.self), String(describing: InsightRecord.self),
    ]

    /// Whether a `ModelContext.didSave` notification can change a score input. Anything unclear counts as relevant.
    public static func isRelevant(saveNotification notification: Notification) -> Bool {
        guard let info = notification.userInfo else { return true }
        // The inserted / updated / deleted lists; every identifier list in the payload counts.
        var seen = false
        for case let identifiers as [PersistentIdentifier] in info.values {
            for identifier in identifiers {
                seen = true
                if !derivedEntities.contains(identifier.entityName) { return true }
            }
        }
        return !seen
    }
}

import DataKit
import Foundation
import SwiftData

/// The bundled exercise catalog read once and kept in memory. The editor, the active workout, the progression engine
/// and the history names all need it; reading the whole table for each of them blocked the main actor on every screen.
/// Invalidated when a catalog sync may have changed it.
final class CatalogCache: @unchecked Sendable {
    private let lock = NSLock()
    private var cached: [ActiveWorkoutModel.CatalogEntry]?

    func entries(in container: ModelContainer) -> [ActiveWorkoutModel.CatalogEntry] {
        lock.lock()
        defer { lock.unlock() }
        if let cached { return cached }
        let context = ModelContext(container)
        let rows = ((try? context.fetch(FetchDescriptor<Exercise>())) ?? []).map {
            ActiveWorkoutModel.CatalogEntry(item: ExerciseListItem($0), pattern: $0.movementPattern, mechanic: $0.mechanic)
        }
        // An empty read (catalog not imported yet) is not remembered.
        if !rows.isEmpty { cached = rows }
        return rows
    }

    func invalidate() {
        lock.lock()
        cached = nil
        lock.unlock()
    }
}

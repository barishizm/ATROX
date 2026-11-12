import Foundation
import SwiftData

/// Writes catalog records into the local store on its own background context. Ids are never changed or removed:
/// existing rows are updated in place, and exercises that disappear from a *full* catalog are archived.
@ModelActor
public actor CatalogImporter {
    public enum Mode: Sendable { case full, delta }

    /// - Returns: number of records written.
    @discardableResult
    public func apply(
        _ records: [CatalogRecord], mode: Mode, version: Int, checksum: String, now: Date = Date()
    ) throws -> Int {
        var existing: [String: Exercise] = [:]
        for exercise in try modelContext.fetch(FetchDescriptor<Exercise>()) { existing[exercise.id] = exercise }

        var seen = Set<String>()
        seen.reserveCapacity(records.count)
        for record in records {
            seen.insert(record.id)
            if let exercise = existing[record.id] {
                exercise.apply(record)
            } else {
                modelContext.insert(Exercise(record: record))
            }
        }
        if mode == .full {
            for (id, exercise) in existing where !seen.contains(id) && !exercise.isArchived {
                exercise.isArchived = true
            }
        }

        if let info = try modelContext.fetch(FetchDescriptor<CatalogInfo>()).first {
            info.version = version
            info.checksum = checksum
            info.syncedAt = now
        } else {
            modelContext.insert(CatalogInfo(version: version, checksum: checksum, importedAt: now))
        }
        try modelContext.save()
        return records.count
    }

    public func installedInfo() throws -> (version: Int, checksum: String)? {
        try modelContext.fetch(FetchDescriptor<CatalogInfo>()).first.map { ($0.version, $0.checksum) }
    }
}

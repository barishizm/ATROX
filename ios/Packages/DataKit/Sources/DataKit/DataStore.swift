import Foundation
import SwiftData

/// Builds the app's `ModelContainer`: on disk in the shared app group (so widgets can read it) or in memory.
public enum DataStore {
    public enum StoreError: Error, Equatable {
        /// The app group is not in the app's entitlements (or the container is unavailable).
        case appGroupUnavailable(String)
    }

    public static let schema = Schema(versionedSchema: SchemaV3.self)

    /// In-memory container for tests and SwiftUI previews.
    public static func inMemory() throws -> ModelContainer {
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, migrationPlan: DataMigrationPlan.self, configurations: configuration)
    }

    /// Production container stored inside the app group container.
    public static func production(
        appGroupID: String,
        fileManager: FileManager = .default,
        resolveContainer: (String) -> URL? = { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0) }
    ) throws -> ModelContainer {
        guard let base = resolveContainer(appGroupID) else {
            throw StoreError.appGroupUnavailable(appGroupID)
        }
        return try onDisk(directory: base, fileManager: fileManager)
    }

    /// On-disk container under `directory` (used by `production` and by tests with a temp folder).
    public static func onDisk(directory: URL, fileManager: FileManager = .default) throws -> ModelContainer {
        let folder = directory.appendingPathComponent("Library/Application Support", isDirectory: true)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        let configuration = ModelConfiguration(schema: schema, url: folder.appendingPathComponent("ATROX.store"))
        return try ModelContainer(for: schema, migrationPlan: DataMigrationPlan.self, configurations: configuration)
    }
}

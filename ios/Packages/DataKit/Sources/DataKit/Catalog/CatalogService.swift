import Foundation
import SwiftData

/// Keeps the local exercise catalog current (P028):
///  1. `bootstrap()` — first launch (or an app update with a newer file) imports the bundled `catalog.v{N}.json`;
///  2. `syncRemote()` — compares `catalog_versions` on the server with the local version and, only if the server is
///     newer, fetches just the exercises changed since the installed version was published.
/// Both run on a background context; neither touches user data, so existing workouts are never affected.
public struct CatalogService: Sendable {
    public typealias PackageLoader = @Sendable () throws -> CatalogPackage

    private let importer: CatalogImporter
    private let loadBundled: PackageLoader
    private let remote: (any CatalogRemote)?
    private let clock: @Sendable () -> Date

    public init(
        modelContainer: ModelContainer,
        bundled: @escaping PackageLoader = { try BundledCatalog.load() },
        remote: (any CatalogRemote)? = nil,
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        importer = CatalogImporter(modelContainer: modelContainer)
        loadBundled = bundled
        self.remote = remote
        self.clock = clock
    }

    public func installedVersion() async throws -> Int? {
        try await importer.installedInfo()?.version
    }

    @discardableResult
    public func bootstrap() async throws -> CatalogBootstrapResult {
        let installed = try await importer.installedInfo()
        let package = try loadBundled()
        if let installed, installed.version >= package.version {
            return .upToDate(version: installed.version)
        }
        // A newer bundled file also covers anything the server had so far; archive logic runs on the full list.
        let count = try await importer.apply(
            package.exercises, mode: .full, version: package.version, checksum: package.checksum, now: clock())
        return .imported(version: package.version, count: count)
    }

    @discardableResult
    public func syncRemote() async throws -> CatalogSyncResult {
        guard let remote else { return .notInstalled }
        guard let installed = try await importer.installedInfo() else { return .notInstalled }
        guard let latest = try await remote.latestVersion(), latest.version > installed.version else {
            return .upToDate(version: installed.version)
        }
        // Changes since the installed version went live; if the server does not know that version, fetch everything.
        let since = try await remote.version(installed.version)?.publishedAt ?? "1970-01-01T00:00:00+00:00"
        let changed = try await remote.changes(since: since)
        try await importer.apply(changed, mode: .delta, version: latest.version, checksum: latest.checksum, now: clock())
        return .updated(from: installed.version, to: latest.version, changed: changed.count)
    }
}

/// Finds and decodes the catalog file bundled with the app.
public enum BundledCatalog {
    /// `catalog.v{N}.json` with the highest N, in the bundle root or a `Catalog` folder.
    public static func url(in bundle: Bundle = .main) -> URL? {
        let candidates = (bundle.urls(forResourcesWithExtension: "json", subdirectory: nil) ?? [])
            + (bundle.urls(forResourcesWithExtension: "json", subdirectory: "Catalog") ?? [])
        return candidates
            .compactMap { url in version(ofFileNamed: url.lastPathComponent).map { ($0, url) } }
            .max { $0.0 < $1.0 }?.1
    }

    static func version(ofFileNamed name: String) -> Int? {
        guard name.hasPrefix("catalog.v"), name.hasSuffix(".json") else { return nil }
        return Int(name.dropFirst("catalog.v".count).dropLast(".json".count))
    }

    public static func load(bundle: Bundle = .main) throws -> CatalogPackage {
        guard let url = url(in: bundle) else { throw CatalogError.bundledCatalogMissing }
        return try CatalogPackage.decode(Data(contentsOf: url, options: .mappedIfSafe))
    }
}

import Foundation
import Observation

/// The user's favorite and recently used exercises (P030). Stored on the device in `UserDefaults` for now; the
/// workout history of P032 becomes the source for "recent" and favorites move into the synced model later
/// (see "Ertelenenler" in docs/ILERLEME.md).
@MainActor
@Observable
public final class ExerciseLists {
    public static let recentLimit = 20
    static let favoritesKey = "exercise.favorites.v1"
    static let recentsKey = "exercise.recents.v1"

    @ObservationIgnored private let defaults: UserDefaults
    /// Insertion order, oldest first.
    public private(set) var favoriteIDs: [String]
    /// Most recent first.
    public private(set) var recentIDs: [String]

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        favoriteIDs = defaults.stringArray(forKey: Self.favoritesKey) ?? []
        recentIDs = defaults.stringArray(forKey: Self.recentsKey) ?? []
    }

    public func isFavorite(_ id: String) -> Bool { favoriteIDs.contains(id) }

    public func toggleFavorite(_ id: String) {
        if let index = favoriteIDs.firstIndex(of: id) { favoriteIDs.remove(at: index) } else { favoriteIDs.append(id) }
        defaults.set(favoriteIDs, forKey: Self.favoritesKey)
    }

    /// Marks exercises as just used (e.g. added to a workout); the last id ends up first.
    public func noteUsed(_ ids: [String]) {
        for id in ids {
            recentIDs.removeAll { $0 == id }
            recentIDs.insert(id, at: 0)
        }
        if recentIDs.count > Self.recentLimit { recentIDs.removeLast(recentIDs.count - Self.recentLimit) }
        defaults.set(recentIDs, forKey: Self.recentsKey)
    }
}

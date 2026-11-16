import Foundation

/// The one place where `UserDefaults` is declared safe to share across concurrency domains.
///
/// The SDK has not marked `UserDefaults` as `Sendable`, but Apple documents it as thread-safe ("You can use
/// UserDefaults from any thread"), and this wrapper only exposes plain reads and writes of property-list values. Every
/// store that needs defaults holds this type, so those stores are checked `Sendable` types and there is a single
/// audited `@unchecked` instead of one per store. Remove it when the SDK annotates `UserDefaults`.
final class SendableDefaults: @unchecked Sendable {
    private let defaults: UserDefaults

    init(_ defaults: UserDefaults) { self.defaults = defaults }

    func data(forKey key: String) -> Data? { defaults.data(forKey: key) }
    func object(forKey key: String) -> Any? { defaults.object(forKey: key) }
    func dictionary(forKey key: String) -> [String: Any]? { defaults.dictionary(forKey: key) }
    func dictionaryRepresentation() -> [String: Any] { defaults.dictionaryRepresentation() }
    func set(_ value: Any?, forKey key: String) { defaults.set(value, forKey: key) }
    func removeObject(forKey key: String) { defaults.removeObject(forKey: key) }
}

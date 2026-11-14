import SwiftUI

extension LocalizedStringKey {
    /// A key built at runtime (`"today.pattern." + id`). Writing `LocalizedStringKey("a.\(id)")` would look up the
    /// interpolated format `a.%@` instead, which is not in the String Catalog.
    static func dynamic(_ key: String) -> LocalizedStringKey { LocalizedStringKey(key) }
}

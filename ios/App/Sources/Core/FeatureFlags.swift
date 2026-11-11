import Foundation

/// Features that can be switched on/off without shipping a new build.
enum FeatureFlag: String, CaseIterable, Sendable {
    case coach
    case social
    case paywall
    case healthKit
}

/// Feature flag values. Defaults are local; a remote source will later feed `applying(remote:)`.
struct FeatureFlags: Sendable, Equatable {
    static let localDefaults: [FeatureFlag: Bool] = [
        .coach: true,
        .social: false,
        .paywall: true,
        .healthKit: false
    ]

    private var values: [FeatureFlag: Bool]

    init(overrides: [FeatureFlag: Bool] = [:]) {
        values = Self.localDefaults.merging(overrides) { _, new in new }
    }

    func isEnabled(_ flag: FeatureFlag) -> Bool {
        values[flag] ?? false
    }

    /// Returns a copy with remote values layered on top of the current ones.
    func applying(remote: [FeatureFlag: Bool]) -> FeatureFlags {
        var copy = self
        copy.values.merge(remote) { _, new in new }
        return copy
    }
}

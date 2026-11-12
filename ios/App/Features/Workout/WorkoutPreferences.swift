import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Settings of the workout screen, stored in `UserDefaults` (`@AppStorage` in views).
enum WorkoutPreferences {
    static let showRirKey = "workout.showRir"
    static let keepAwakeKey = "workout.keepAwake"

    /// RIR picker is on by default; the user can turn it off in Settings.
    static func showsRir(_ defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: showRirKey) as? Bool ?? true
    }

    @MainActor
    static func setIdleTimerDisabled(_ disabled: Bool) {
        #if canImport(UIKit)
        UIApplication.shared.isIdleTimerDisabled = disabled
        #endif
    }
}

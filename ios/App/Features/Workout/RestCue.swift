import AudioToolbox
import DesignSystem
import Foundation

/// Sound and haptic when a rest countdown runs out while the app is open.
enum RestCue {
    @MainActor
    static func play() {
        Haptics.play(.success)
        AudioServicesPlaySystemSound(1007)
    }
}

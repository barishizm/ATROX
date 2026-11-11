#if canImport(UIKit)
import UIKit
#endif

/// Haptic feedback helper. No-op where haptics are unavailable (macOS tests, previews).
@MainActor
public enum Haptics {
    public enum Kind: Sendable, CaseIterable {
        case light, medium, heavy, selection, success, warning, error
    }

    public static func play(_ kind: Kind) {
        #if canImport(UIKit) && !os(visionOS)
        switch kind {
        case .light: UIImpactFeedbackGenerator(style: .light).impactOccurred()
        case .medium: UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        case .heavy: UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        case .selection: UISelectionFeedbackGenerator().selectionChanged()
        case .success: UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .warning: UINotificationFeedbackGenerator().notificationOccurred(.warning)
        case .error: UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
        #endif
    }
}

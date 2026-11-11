import SwiftUI

/// Shadow tokens. In the dark theme elevation is mostly expressed by surface lightness, so
/// shadows stay subtle; they matter more in the light theme.
public struct Elevation: Sendable {
    public let opacity: Double
    public let radius: CGFloat
    public let y: CGFloat

    public static let none = Elevation(opacity: 0, radius: 0, y: 0)
    public static let card = Elevation(opacity: 0.18, radius: 12, y: 4)
    public static let raised = Elevation(opacity: 0.28, radius: 24, y: 10)
}

extension View {
    /// Applies an `Elevation` shadow token.
    public func dsShadow(_ elevation: Elevation) -> some View {
        shadow(color: .black.opacity(elevation.opacity), radius: elevation.radius, x: 0, y: elevation.y)
    }
}

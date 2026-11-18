import SwiftUI

private struct GlassSurfacesKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// When true, DesignSystem buttons, cards and selectable cards draw as Liquid Glass instead of opaque surfaces.
    /// Set it on a screen that sits over a photo or illustration (e.g. onboarding), never on plain app chrome.
    public var dsGlassSurfaces: Bool {
        get { self[GlassSurfacesKey.self] }
        set { self[GlassSurfacesKey.self] = newValue }
    }
}

extension View {
    /// Draws DesignSystem controls below as Liquid Glass; see `EnvironmentValues.dsGlassSurfaces`.
    public func dsGlassSurfaces(_ enabled: Bool = true) -> some View {
        environment(\.dsGlassSurfaces, enabled)
    }

    /// Interactive-looking glass fill for a custom control, with an optional tint (e.g. the accent for a selection).
    public func dsGlassFill(_ tint: Color? = nil, cornerRadius: CGFloat = Radius.md, interactive: Bool = false) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        var glass = Glass.regular.tint(tint ?? Color.black.opacity(0.4))
        if interactive { glass = glass.interactive() }
        return glassEffect(glass, in: shape)
    }
}

/// The darker tint every glass surface over a photo gets, so text on it stays readable.
public let dsGlassDim = Color.black.opacity(0.4)

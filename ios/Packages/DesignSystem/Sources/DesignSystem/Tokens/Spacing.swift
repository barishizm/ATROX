import SwiftUI

/// Spacing scale (points). Use these instead of literals so density can be tuned in one place.
public enum Spacing {
    public static let xxs: CGFloat = 2
    public static let xs: CGFloat = 4
    public static let sm: CGFloat = 8
    public static let md: CGFloat = 16
    public static let lg: CGFloat = 24
    public static let xl: CGFloat = 32
    public static let xxl: CGFloat = 48
}

/// Corner radius scale. Always paired with `.continuous` corner style.
public enum Radius {
    public static let sm: CGFloat = 8
    public static let md: CGFloat = 14
    public static let lg: CGFloat = 20
    public static let xl: CGFloat = 28
}

/// Minimum interactive size (HIG: 44pt).
public enum HitTarget {
    public static let minimum: CGFloat = 44
    public static let button: CGFloat = 52
}

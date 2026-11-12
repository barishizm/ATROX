import Foundation

/// Default rest after a set when the program does not say: longer for compound lifts, shorter for isolation.
public enum RestDefaults {
    public static let compoundSeconds = 120
    public static let isolationSeconds = 75
    public static let fallbackSeconds = 90

    /// The routine row's own rest wins; else by the catalog `mechanic` ("compound" / "isolation"); else 90 s.
    public static func seconds(program: Int?, mechanic: String?) -> Int {
        if let program, program > 0 { return program }
        switch mechanic?.lowercased() {
        case "compound": return compoundSeconds
        case "isolation": return isolationSeconds
        default: return fallbackSeconds
        }
    }
}

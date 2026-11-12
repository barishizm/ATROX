import Foundation

/// Pure state of the workout's custom numeric keypad (P036): one number being typed, in the user's display unit.
/// The internal text always uses "." as the decimal mark; the view shows the locale's.
struct WorkoutKeypad: Equatable {
    enum Field: Equatable { case weight, reps }

    let field: Field
    private(set) var text: String
    /// True until the first key press: the next digit replaces the pre-filled value instead of appending to it.
    private(set) var isFresh: Bool

    static let maxLength = 6

    init(field: Field, value: Double) {
        self.field = field
        text = Self.format(value, field: field)
        isFresh = true
    }

    var allowsDecimal: Bool { field == .weight }
    var value: Double? { Double(text) }

    mutating func digit(_ digit: Int) {
        guard (0...9).contains(digit) else { return }
        let character = Character(String(digit))
        if isFresh || text == "0" {
            text = String(character)
        } else if text.count < Self.maxLength {
            text.append(character)
        }
        isFresh = false
    }

    mutating func decimal() {
        guard allowsDecimal else { return }
        if isFresh {
            text = "0."
        } else if !text.contains("."), text.count < Self.maxLength {
            text = text.isEmpty ? "0." : text + "."
        }
        isFresh = false
    }

    mutating func backspace() {
        if isFresh { text = "" } else { text = String(text.dropLast()) }
        isFresh = false
    }

    /// ± one step (plate step for weight, one rep for reps); never below zero.
    mutating func step(_ direction: Int, by amount: Double) {
        let next = max(0, (value ?? 0) + Double(direction) * amount)
        text = Self.format(next, field: field)
        isFresh = true
    }

    /// "Same as before": takes the given value, as if the user typed it.
    mutating func replace(with newValue: Double) {
        text = Self.format(newValue, field: field)
        isFresh = true
    }

    static func format(_ value: Double, field: Field) -> String {
        let clean = max(0, value.isFinite ? value : 0)
        if field == .reps { return String(Int(clean.rounded())) }
        let rounded = (clean * 100).rounded() / 100
        if rounded == rounded.rounded() { return String(Int(rounded)) }
        var text = String(format: "%.2f", rounded)
        while text.hasSuffix("0") { text.removeLast() }
        return text
    }

    /// The text for the screen: `text` with the locale's decimal mark and a trailing mark kept while typing.
    func displayText(decimalSeparator: String) -> String {
        text.isEmpty ? "0" : text.replacingOccurrences(of: ".", with: decimalSeparator)
    }
}

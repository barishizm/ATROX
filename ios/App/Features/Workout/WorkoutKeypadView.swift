import DesignSystem
import SwiftUI

/// The numeric keypad shown under the set list while a weight or reps field is being edited.
struct WorkoutKeypadView: View {
    let model: ActiveWorkoutModel
    let editing: ActiveWorkoutModel.Editing

    private let columns = Array(repeating: GridItem(.flexible(), spacing: Spacing.sm), count: 4)

    var body: some View {
        VStack(spacing: Spacing.sm) {
            header
            LazyVGrid(columns: columns, spacing: Spacing.sm) {
                ForEach([1, 2, 3], id: \.self) { digit($0) }
                stepKey(-1)
                ForEach([4, 5, 6], id: \.self) { digit($0) }
                stepKey(1)
                ForEach([7, 8, 9], id: \.self) { digit($0) }
                key("workout.keypad.same", id: "keypad-same") { model.pressSameAsPrevious() }
                if editing.keypad.allowsDecimal {
                    key(Text(verbatim: model.decimalSeparator), id: "keypad-decimal") { model.pressDecimal() }
                } else {
                    Color.clear.frame(height: HitTarget.button)
                }
                digit(0)
                iconKey("delete.left", label: "workout.keypad.delete", id: "keypad-delete") { model.pressBackspace() }
                Button {
                    Task { await model.advance() }
                } label: {
                    Image(systemName: "arrow.right").font(DSFont.headline).frame(maxWidth: .infinity, minHeight: HitTarget.button)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityLabel("workout.keypad.next")
                .accessibilityIdentifier("keypad-next")
            }
        }
        .padding(Spacing.md)
        .background(.bar)
        .accessibilityIdentifier("workout-keypad")
    }

    private var header: some View {
        HStack {
            Text(editing.keypad.field == .weight ? "workout.field.weight \(model.unit.symbol)" : "workout.field.reps")
                .font(DSFont.callout)
                .foregroundStyle(DSColor.textSecondary)
            Spacer()
            Text(verbatim: editing.keypad.displayText(decimalSeparator: model.decimalSeparator))
                .font(DSFont.numericLarge)
                .monospacedDigit()
                .accessibilityIdentifier("keypad-value")
            Button { Task { await model.dismissKeypad() } } label: { Image(systemName: "keyboard.chevron.compact.down") }
                .accessibilityLabel("workout.keypad.close")
                .accessibilityIdentifier("keypad-close")
        }
    }

    private func digit(_ value: Int) -> some View {
        key(Text(verbatim: String(value)), id: "keypad-\(value)") { model.press(digit: value) }
    }

    private func stepKey(_ direction: Int) -> some View {
        let amount = editing.keypad.field == .weight ? model.plateStep : 1
        let text = Text(verbatim: (direction > 0 ? "+" : "−") + WorkoutKeypad.format(amount, field: editing.keypad.field))
        return key(text, id: direction > 0 ? "keypad-plus" : "keypad-minus") { model.pressStep(direction) }
    }

    private func key(_ title: LocalizedStringKey, id: String, action: @escaping () -> Void) -> some View {
        key(Text(title), id: id, action: action)
    }

    private func key(_ title: Text, id: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.play(.light)
            action()
        } label: {
            title.font(DSFont.headline).frame(maxWidth: .infinity, minHeight: HitTarget.button)
        }
        .buttonStyle(.bordered)
        .accessibilityIdentifier(id)
    }

    private func iconKey(_ systemName: String, label: LocalizedStringKey, id: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.play(.light)
            action()
        } label: {
            Image(systemName: systemName).frame(maxWidth: .infinity, minHeight: HitTarget.button)
        }
        .buttonStyle(.bordered)
        .accessibilityLabel(label)
        .accessibilityIdentifier(id)
    }
}

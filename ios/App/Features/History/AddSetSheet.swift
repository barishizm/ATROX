import DataKit
import DesignSystem
import SwiftUI

/// "Add Set": weight × reps, how many reps were left (0–4+ in half steps) and the day. Saves one finished set to the
/// history without starting a workout.
struct AddSetSheet: View {
    let model: ExerciseHistoryModel
    /// Called after a set was saved, so lists elsewhere reload.
    var onSaved: () -> Void = {}
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @State private var weightText = ""
    @State private var repsText = ""
    @State private var rir = 2.5
    @State private var date = Date()
    @State private var pickingDate = false
    @State private var failed = false
    @State private var saving = false
    @FocusState private var focus: Field?

    private enum Field { case weight, reps }

    /// 0, 0.5 … 4 and the last stop, "4+" (stored as 4.5).
    private static let stops = Array(stride(from: 0.0, through: 4.5, by: 0.5))

    private var weightKg: Double? {
        let trimmed = weightText.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return 0 }
        return WeightFormat.kilograms(from: trimmed, unit: model.context.unit, locale: locale)
    }

    private var reps: Int? { Int(repsText.trimmingCharacters(in: .whitespaces)).flatMap { (1...100).contains($0) ? $0 : nil } }

    private var canSave: Bool { !saving && weightKg != nil && reps != nil }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(DSColor.separator)
            ScrollView {
                VStack(spacing: 0) {
                    if pickingDate {
                        DatePicker("addset.date", selection: $date, in: ...Date(), displayedComponents: .date)
                            .datePickerStyle(.graphical).labelsHidden()
                            .padding(.horizontal, Spacing.md)
                        Divider().overlay(DSColor.separator)
                    }
                    inputs
                    Divider().overlay(DSColor.separator)
                    rirSection
                }
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            saveButton.background(DSColor.surface)
        }
        .background(DSColor.surface)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .onAppear { focus = .weight }
        .alert("addset.error", isPresented: $failed) { Button("routine.action.ok", role: .cancel) {} }
        .accessibilityIdentifier("add-set-sheet")
    }

    private var header: some View {
        HStack(spacing: Spacing.md) {
            Text("exprogress.addSet").font(DSFont.title).foregroundStyle(DSColor.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            Button {
                focus = nil
                withAnimation { pickingDate.toggle() }
            } label: {
                Image(systemName: "calendar").frame(width: HitTarget.minimum, height: HitTarget.minimum)
            }
            .foregroundStyle(pickingDate ? DSColor.accent : DSColor.textPrimary)
            .accessibilityLabel("addset.date")
            .accessibilityValue(Text(date, format: .dateTime.day().month(.abbreviated).year()))
            .accessibilityIdentifier("add-set-date")
            Button { dismiss() } label: {
                Image(systemName: "xmark").frame(width: HitTarget.minimum, height: HitTarget.minimum)
            }
            .foregroundStyle(DSColor.textPrimary)
            .accessibilityLabel("addset.close")
            .accessibilityIdentifier("add-set-close")
        }
        .font(.title3.weight(.medium))
        .padding(.leading, Spacing.md).padding(.trailing, Spacing.sm).padding(.top, Spacing.md)
    }

    private var inputs: some View {
        HStack(alignment: .bottom, spacing: Spacing.sm) {
            HStack(alignment: .lastTextBaseline, spacing: Spacing.sm) {
                field("addset.weight", text: $weightText, keyboard: .decimalPad, which: .weight)
                Text(verbatim: model.context.unit.symbol).font(DSFont.headline).foregroundStyle(DSColor.textPrimary)
            }
            Text(verbatim: "×").font(DSFont.body).foregroundStyle(DSColor.textSecondary).padding(.bottom, Spacing.sm)
            field("addset.reps", text: $repsText, keyboard: .numberPad, which: .reps)
        }
        .padding(Spacing.md)
    }

    private func field(_ prompt: LocalizedStringKey, text: Binding<String>, keyboard: UIKeyboardType, which: Field) -> some View {
        VStack(spacing: Spacing.xs) {
            TextField("", text: text, prompt: Text(prompt).font(DSFont.callout).foregroundColor(DSColor.textSecondary))
                .keyboardType(keyboard)
                .focused($focus, equals: which)
                .font(DSFont.numericLarge).foregroundStyle(DSColor.textPrimary)
                .frame(minHeight: HitTarget.minimum)
            Rectangle().fill(focus == which ? DSColor.accent : DSColor.textPrimary.opacity(0.6)).frame(height: 2)
        }
        .accessibilityIdentifier("add-set-\(which == .weight ? "weight" : "reps")")
    }

    private var rirSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("addset.rir").font(DSFont.callout).foregroundStyle(DSColor.textSecondary)
            HStack {
                ForEach(["0", "1", "2", "3", "4", "4+"], id: \.self) { label in
                    Text(verbatim: label).font(DSFont.callout).foregroundStyle(DSColor.textPrimary)
                        .frame(maxWidth: .infinity)
                }
            }
            .accessibilityHidden(true)
            Slider(value: $rir, in: 0...4.5, step: 0.5)
                .tint(DSColor.accent)
                .accessibilityLabel("addset.rir")
                .accessibilityValue(Text(verbatim: Self.valueText(rir)))
                .accessibilityIdentifier("add-set-rir")
            Text(LocalizedStringKey.dynamic("addset.rir.caption.\(Int(rir * 2))"))
                .font(DSFont.body).foregroundStyle(DSColor.textPrimary)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        }
        .padding(Spacing.md)
    }

    private static func valueText(_ value: Double) -> String { value >= 4.5 ? "4+" : value.formatted() }

    private var saveButton: some View {
        PrimaryButton("addset.save") { Task { await save() } }
            .disabled(!canSave)
            .padding(Spacing.md)
            .accessibilityIdentifier("add-set-save")
    }

    private func save() async {
        guard let weightKg, let reps else { return }
        saving = true
        let saved = await model.addSet(weightKg: weightKg, reps: reps, rir: rir, on: date)
        saving = false
        if saved {
            onSaved()
            dismiss()
        } else {
            failed = true
        }
    }
}

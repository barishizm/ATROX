import DataKit
import DesignSystem
import SwiftUI

/// Typing a food in by hand, or editing a saved entry.
struct ManualFoodView: View {
    let editing: FoodEntrySnapshot?
    let onSave: (FoodEntryInput) async -> Bool
    let onClose: () -> Void

    @State private var name: String
    @State private var meal: MealType
    @State private var eatenAt: Date
    @State private var calories: Double
    @State private var protein: Double
    @State private var carbs: Double
    @State private var fat: Double
    @State private var grams: Double
    @State private var saving = false
    @State private var failed = false

    init(editing: FoodEntrySnapshot? = nil, onSave: @escaping (FoodEntryInput) async -> Bool, onClose: @escaping () -> Void) {
        self.editing = editing
        self.onSave = onSave
        self.onClose = onClose
        let input = editing?.input
        _name = State(initialValue: input?.name ?? "")
        _meal = State(initialValue: input?.meal ?? MealType.suggested(for: Date()))
        _eatenAt = State(initialValue: input?.eatenAt ?? Date())
        _calories = State(initialValue: input?.calories ?? 0)
        _protein = State(initialValue: input?.proteinG ?? 0)
        _carbs = State(initialValue: input?.carbsG ?? 0)
        _fat = State(initialValue: input?.fatG ?? 0)
        _grams = State(initialValue: input?.grams ?? 0)
    }

    private var canSave: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty && calories > 0 }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("nutrition.manual.name", text: $name).accessibilityIdentifier("manual-name")
                    Picker("nutrition.editor.meal", selection: $meal) {
                        ForEach(MealType.allCases, id: \.self) { Text($0.titleKey).tag($0) }
                    }
                    DatePicker("nutrition.editor.time", selection: $eatenAt, in: ...Date(), displayedComponents: [.date, .hourAndMinute])
                }
                Section {
                    NumberField(title: "nutrition.manual.calories", value: $calories, unit: "kcal", maximum: 20_000)
                    NumberField(title: "nutrition.macro.protein", value: $protein, unit: "g", maximum: 2000)
                    NumberField(title: "nutrition.macro.carbs", value: $carbs, unit: "g", maximum: 2000)
                    NumberField(title: "nutrition.macro.fat", value: $fat, unit: "g", maximum: 2000)
                    NumberField(title: "nutrition.manual.grams", value: $grams, unit: "g", maximum: 20_000)
                } footer: {
                    if failed { Text("nutrition.save.failed").foregroundStyle(DSColor.error) }
                }
            }
            .scrollContentBackground(.hidden)
            .background(DSColor.background.ignoresSafeArea())
            .navigationTitle(editing == nil ? "nutrition.manual.title" : "nutrition.manual.edit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("common.cancel", action: onClose) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("nutrition.editor.save") { save() }.disabled(!canSave || saving).accessibilityIdentifier("manual-save")
                }
            }
        }
        .accessibilityIdentifier("manual-food")
    }

    private func save() {
        saving = true
        failed = false
        let input = FoodEntryInput(
            eatenAt: eatenAt, meal: meal, name: name.trimmingCharacters(in: .whitespaces), calories: calories, proteinG: protein, carbsG: carbs,
            fatG: fat, grams: grams > 0 ? grams : nil, source: editing?.input.source ?? .manual, items: editing?.input.items ?? []
        )
        Task {
            let saved = await onSave(input)
            saving = false
            if saved { onClose() } else { failed = true }
        }
    }
}

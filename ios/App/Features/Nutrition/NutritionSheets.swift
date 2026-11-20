import DataKit
import DesignSystem
import SwiftUI

/// Shared chrome of the small input sheets: a form with Cancel and Save.
private struct InputSheet<Content: View>: View {
    let title: LocalizedStringKey
    let canSave: Bool
    let onSave: () async -> Bool
    @ViewBuilder let content: () -> Content
    @Environment(\.dismiss) private var dismiss
    @State private var failed = false

    var body: some View {
        NavigationStack {
            Form {
                content()
                if failed { Text("nutrition.save.failed").foregroundStyle(DSColor.error) }
            }
            .scrollContentBackground(.hidden)
            .background(DSColor.background.ignoresSafeArea())
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("common.cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("nutrition.editor.save") { Task { if await onSave() { dismiss() } else { failed = true } } }.disabled(!canSave)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

/// A workout or activity with its length and the calories it burned.
struct ActivitySheet: View {
    let onSave: (String, Double, Double) async -> Bool
    @State private var name = ""
    @State private var minutes = 0.0
    @State private var kcal = 0.0

    var body: some View {
        InputSheet(
            title: "nutrition.activity.add", canSave: !name.trimmingCharacters(in: .whitespaces).isEmpty && minutes > 0,
            onSave: { await onSave(name.trimmingCharacters(in: .whitespaces), minutes, kcal) }
        ) {
            Section {
                TextField("nutrition.activity.name", text: $name).accessibilityIdentifier("activity-name")
                NumberField(title: "nutrition.activity.duration", value: $minutes, unit: "min", maximum: 1440)
                NumberField(title: "nutrition.activity.burned", value: $kcal, unit: "kcal", maximum: 10_000)
            }
        }
    }
}

struct StepsSheet: View {
    let onSave: (Double) async -> Bool
    @State private var steps = 0.0

    var body: some View {
        InputSheet(title: "nutrition.steps.addmanual", canSave: steps > 0, onSave: { await onSave(steps) }) {
            Section { NumberField(title: "nutrition.steps.count", value: $steps, unit: "", maximum: 100_000) }
        }
    }
}

struct NoteSheet: View {
    let existing: DiaryLogSnapshot?
    let onSave: (String, String) async -> Bool
    @State private var mood: String
    @State private var text: String

    init(existing: DiaryLogSnapshot?, onSave: @escaping (String, String) async -> Bool) {
        self.existing = existing
        self.onSave = onSave
        _mood = State(initialValue: existing?.input.label ?? "good")
        _text = State(initialValue: existing?.input.text ?? "")
    }

    var body: some View {
        InputSheet(title: "nutrition.note.title", canSave: true, onSave: { await onSave(mood, text) }) {
            Section {
                HStack {
                    ForEach(NutritionModel.moods, id: \.self) { value in
                        Button { mood = value } label: {
                            Text(verbatim: NotesCard.emoji(value)).font(.largeTitle).padding(Spacing.xs)
                                .background(mood == value ? DSColor.surfaceRaised : Color.clear, in: Circle())
                                .frame(maxWidth: .infinity, minHeight: HitTarget.minimum)
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(mood == value ? .isSelected : [])
                    }
                }
                TextField("nutrition.note.placeholder", text: $text, axis: .vertical).lineLimit(3...8)
            }
        }
    }
}

/// Picks a fasting plan and starts it.
struct FastPlanSheet: View {
    let onStart: (Double, String) async -> Bool
    @Environment(\.dismiss) private var dismiss
    private let plans: [(hours: Double, label: String)] = [(12, "12:12"), (14, "14:10"), (16, "16:8"), (18, "18:6"), (20, "20:4")]

    var body: some View {
        NavigationStack {
            List(plans, id: \.label) { plan in
                Button {
                    Task { if await onStart(plan.hours, plan.label) { dismiss() } }
                } label: {
                    HStack {
                        Text(verbatim: plan.label).font(DSFont.headline)
                        Spacer()
                        Text("nutrition.fasting.hours \(Int(plan.hours))").foregroundStyle(DSColor.textSecondary)
                    }
                    .frame(minHeight: HitTarget.minimum)
                }
                .foregroundStyle(DSColor.textPrimary)
                .accessibilityIdentifier("fast-plan-\(plan.label)")
                .listRowBackground(DSColor.surface)
            }
            .scrollContentBackground(.hidden)
            .background(DSColor.background.ignoresSafeArea())
            .navigationTitle("nutrition.fasting.choose")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("common.cancel") { dismiss() } } }
        }
        .presentationDetents([.medium])
    }
}

/// A weight typed in the user's unit: the goal weight, or today's weigh-in.
struct GoalWeightSheet: View {
    let title: LocalizedStringKey
    let field: LocalizedStringKey
    let unit: WeightUnit
    let current: Double?
    let onSave: (Double) async -> Bool
    @State private var value: Double

    init(title: LocalizedStringKey, field: LocalizedStringKey, unit: WeightUnit, current: Double?, onSave: @escaping (Double) async -> Bool) {
        self.title = title
        self.field = field
        self.unit = unit
        self.current = current
        self.onSave = onSave
        _value = State(initialValue: current.map { (unit.value(fromKilograms: $0) * 10).rounded() / 10 } ?? 0)
    }

    var body: some View {
        InputSheet(title: title, canSave: value > 0, onSave: { await onSave(unit.kilograms(from: value)) }) {
            Section { NumberField(title: field, value: $value, unit: unit.symbol, maximum: 900) }
        }
    }
}

/// The weight trend and the weigh-ins, newest first.
struct WeightProgressSheet: View {
    let model: NutritionModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale

    private var unit: WeightUnit { model.profile?.weightUnit ?? .kilograms }

    var body: some View {
        NavigationStack {
            List {
                if model.weights.isEmpty {
                    EmptyState(systemImage: "chart.xyaxis.line", title: "measurements.empty.title", message: "measurements.empty.message")
                        .listRowBackground(Color.clear)
                } else {
                    Section("measurements.chart.title") {
                        WeightChart(points: MeasurementTrend.points(from: model.weights), unit: unit)
                    }
                    .listRowBackground(DSColor.surface)
                    Section("measurements.history") {
                        ForEach(model.weights) { row in
                            HStack {
                                Text(row.input.date.formatted(.dateTime.day().month().year().locale(locale)))
                                Spacer()
                                Text(verbatim: unit.value(fromKilograms: row.input.weightKg)
                                    .formatted(.number.precision(.fractionLength(0...1)).locale(locale)) + " " + unit.symbol)
                                    .font(DSFont.numericSmall)
                            }
                        }
                        .onDelete { offsets in
                            let ids = offsets.map { model.weights[$0].id }
                            Task { for id in ids { await model.deleteWeight(id: id) } }
                        }
                    }
                    .listRowBackground(DSColor.surface)
                }
            }
            .scrollContentBackground(.hidden)
            .background(DSColor.background.ignoresSafeArea())
            .navigationTitle("nutrition.weight.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("nutrition.calendar.done") { dismiss() } } }
        }
    }
}

/// Where the daily target comes from.
struct NutritionSourcesSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    Text("nutrition.sources.intro")
                    Text("nutrition.sources.bmr")
                    Text("nutrition.sources.protein")
                    Text("nutrition.sources.meals")
                    Text("nutrition.sources.water")
                    Text("nutrition.sources.disclaimer").font(DSFont.footnote).foregroundStyle(DSColor.textSecondary)
                }
                .font(DSFont.callout).foregroundStyle(DSColor.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading).padding(Spacing.md)
            }
            .background(DSColor.background.ignoresSafeArea())
            .navigationTitle("nutrition.sources.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("nutrition.calendar.done") { dismiss() } } }
        }
    }
}

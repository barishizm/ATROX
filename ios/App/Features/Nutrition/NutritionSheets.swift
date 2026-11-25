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

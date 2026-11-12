import DataKit
import DesignSystem
import SwiftUI

/// Targets of one routine exercise: sets, rep range, RIR, rest and a note. Saved when the user taps "Done".
struct RoutineExerciseSheet: View {
    let name: String
    let original: RoutineExerciseInput
    let onSave: (RoutineExerciseInput) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var sets: Int
    @State private var useReps: Bool
    @State private var repsMin: Int
    @State private var repsMax: Int
    @State private var useRir: Bool
    @State private var rir: Int
    @State private var useRest: Bool
    @State private var rest: Int
    @State private var notes: String

    init(name: String, input: RoutineExerciseInput, onSave: @escaping (RoutineExerciseInput) -> Void) {
        self.name = name
        original = input
        self.onSave = onSave
        _sets = State(initialValue: input.targetSets)
        _useReps = State(initialValue: input.targetRepsMin != nil || input.targetRepsMax != nil)
        _repsMin = State(initialValue: input.targetRepsMin ?? input.targetRepsMax ?? 8)
        _repsMax = State(initialValue: input.targetRepsMax ?? input.targetRepsMin ?? 12)
        _useRir = State(initialValue: input.targetRir != nil)
        _rir = State(initialValue: input.targetRir ?? 2)
        _useRest = State(initialValue: input.restSeconds != nil)
        _rest = State(initialValue: input.restSeconds ?? 90)
        _notes = State(initialValue: input.notes ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Stepper(value: $sets, in: 1...20) { Text("routine.field.sets \(sets)") }
                        .accessibilityIdentifier("routine-sets-stepper")
                    Toggle("routine.field.reps", isOn: $useReps)
                    if useReps {
                        Stepper(value: $repsMin, in: 1...100) { Text("routine.field.min \(repsMin)") }
                            .onChange(of: repsMin) { _, new in if new > repsMax { repsMax = new } }
                        Stepper(value: $repsMax, in: 1...100) { Text("routine.field.max \(repsMax)") }
                            .onChange(of: repsMax) { _, new in if new < repsMin { repsMin = new } }
                    }
                    Toggle("routine.field.rir", isOn: $useRir)
                    if useRir {
                        Stepper(value: $rir, in: 0...10) { Text("routine.summary.rir \(rir)") }
                    }
                    Toggle("routine.field.rest", isOn: $useRest)
                    if useRest {
                        Stepper(value: $rest, in: 0...600, step: 15) { Text(verbatim: RoutineDayView.clock(rest)) }
                    }
                } header: {
                    Text(verbatim: name)
                }
                Section("routine.field.notes") {
                    TextField("routine.field.notes", text: $notes, axis: .vertical).lineLimit(1...4)
                }
            }
            .navigationTitle("routine.exercise.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("routine.action.cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("routine.action.done") {
                        onSave(result)
                        dismiss()
                    }
                    .accessibilityIdentifier("routine-exercise-done")
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var result: RoutineExerciseInput {
        var input = original
        input.targetSets = sets
        input.targetRepsMin = useReps ? repsMin : nil
        input.targetRepsMax = useReps ? repsMax : nil
        input.targetRir = useRir ? rir : nil
        input.restSeconds = useRest ? rest : nil
        let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        input.notes = trimmed.isEmpty ? nil : trimmed
        return input
    }
}

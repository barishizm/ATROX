import DataKit
import Foundation
import Observation

/// What the history screens (P042) share: the user's repositories, the editor that keeps records true, display
/// settings and the exercise names. Built by `AppContainer.makeHistoryContext()`.
struct HistoryContext: Sendable {
    let userId: UUID
    let workouts: any WorkoutRepository
    let editor: WorkoutHistoryEditor
    let routines: any RoutineRepository
    let records: SwiftDataPersonalRecordService
    let unit: WeightUnit
    let locale: Locale
    let languageCode: String
    /// Exercise id (catalog slug or custom UUID string) → name in the app language.
    let loadNames: @Sendable () async -> [String: String]

    func weightText(_ kg: Double) -> String { WeightFormat.string(kilograms: kg, unit: unit, locale: locale) }

    /// "100 kg × 5" for a set.
    func setText(_ input: SetInput) -> String { "\(weightText(input.weightKg)) × \(input.reps)" }

    /// "1 h 05 min" / "42 min".
    static func durationText(_ seconds: TimeInterval) -> String {
        let minutes = max(0, Int((seconds / 60).rounded()))
        return minutes >= 60 ? String(format: "%d h %02d min", minutes / 60, minutes % 60) : "\(minutes) min"
    }

    static func id(of ref: ExerciseRef) -> String {
        switch ref {
        case .catalog(let id): id
        case .custom(let id): id.uuidString
        }
    }
}

/// Changes to the history that other screens need to hear about: a version counter (lists reload when it moves) and
/// the delete that can still be undone.
@MainActor
@Observable
final class HistoryEvents {
    struct PendingUndo: Identifiable, Equatable {
        let id: UUID
        let title: String
    }

    private(set) var version = 0
    var undo: PendingUndo?

    func changed() { version += 1 }
}

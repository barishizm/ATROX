import CoachKit
import DataKit
import DesignSystem
import Foundation
import Observation
import StrengthKit

enum ChangeDirection { case up, down, flat }

/// State of the "workout finished" screen (P041): the numbers (`WorkoutSummary`, computed in DataKit) plus the
/// optional name, note and feeling the user adds. Nothing is stored until `save()`.
@MainActor
@Observable
final class WorkoutSummaryModel {
    let workout: WorkoutSnapshot
    let summary: WorkoutSummary
    let unit: WeightUnit
    let names: [ExerciseRef: String]
    var name: String
    var notes: String
    var rating: Int?
    private(set) var errorKey: String?
    /// The coach's comment on this workout (P083): hidden until one could appear, a skeleton while it is written.
    private(set) var comment: CommentState = .hidden

    enum CommentState: Equatable {
        case hidden
        case loading
        case ready(CoachComment)
    }

    @ObservationIgnored private let repository: any WorkoutRepository
    @ObservationIgnored private let comments: CoachCommentProvider?
    @ObservationIgnored private let language: String
    @ObservationIgnored private let decimalSeparator: String

    init(
        workout: WorkoutSnapshot, summary: WorkoutSummary, unit: WeightUnit, names: [ExerciseRef: String],
        repository: any WorkoutRepository, decimalSeparator: String = ".", comments: CoachCommentProvider? = nil, language: String = "en"
    ) {
        self.comments = comments
        self.language = language
        self.workout = workout
        self.summary = summary
        self.unit = unit
        self.names = names
        self.repository = repository
        self.decimalSeparator = decimalSeparator
        name = workout.name ?? ""
        notes = workout.notes ?? ""
        rating = workout.rating
    }

    // MARK: Display

    var volumeText: String { Self.number(unit.value(fromKilograms: summary.totalVolumeKg), separator: decimalSeparator) }
    var durationText: String { ActiveWorkoutFormat.clock(summary.duration) }

    /// Muscle name → 0…1 intensity for `MuscleMapView`; catalog names the map does not know are ignored.
    var muscleIntensities: [Muscle: Double] {
        var load: [Muscle: Double] = [:]
        for (name, value) in summary.muscleLoad {
            if let muscle = Muscle(rawValue: name) { load[muscle, default: 0] += value }
        }
        return MuscleIntensities.heatmap(load)
    }

    struct RecordRow: Identifiable, Equatable {
        let id: UUID
        let exercise: String
        let kind: RecordKind
        let valueText: String
    }

    var recordRows: [RecordRow] {
        summary.records.map { hit in
            RecordRow(
                id: hit.setId, exercise: names[hit.ref] ?? "—", kind: hit.kind, valueText: recordValue(hit)
            )
        }
    }

    private func recordValue(_ hit: PersonalRecordHit) -> String {
        switch hit.kind {
        case .weight, .e1rm, .volume:
            "\(Self.number(unit.value(fromKilograms: hit.value), separator: decimalSeparator)) \(unit.symbol)"
        case .reps:
            Self.number(hit.value, separator: decimalSeparator)
        }
    }

    struct Change: Equatable {
        let text: String
        let direction: ChangeDirection
    }

    /// "+1,200 kg (+12 %)" against the previous comparable workout; nil for a first workout.
    var volumeChange: Change? {
        guard let comparison = summary.comparison else { return nil }
        let delta = unit.value(fromKilograms: comparison.volumeDeltaKg)
        let sign = delta > 0 ? "+" : delta < 0 ? "−" : ""
        var text = "\(sign)\(Self.number(abs(delta), separator: decimalSeparator)) \(unit.symbol)"
        if let percent = comparison.volumePercent {
            text += " (\(sign)\(Self.number(abs(percent), separator: decimalSeparator, maxFraction: 0)) %)"
        }
        return Change(text: text, direction: delta > 0 ? .up : delta < 0 ? .down : .flat)
    }

    // MARK: Coach comment (P083)

    /// Asks for the comment once. Any failure hides the section instead of showing an error.
    func loadComment() async {
        guard let comments, comment == .hidden, await comments.mightCommentOnWorkout(language: language) else { return }
        comment = .loading
        let digest = CoachDigestBuilder.workout(summary, workout: workout, names: names)
        if let written = await comments.workoutComment(digest, language: language) {
            comment = .ready(written)
        } else {
            comment = .hidden
        }
    }

    // MARK: Saving

    /// Writes the name, note and feeling. Returns whether it worked (the screen stays open otherwise).
    func save() async -> Bool {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try await repository.updateDetails(
                id: workout.id, name: cleanName.isEmpty ? nil : cleanName, notes: cleanNotes.isEmpty ? nil : cleanNotes
            )
            try await repository.setRating(id: workout.id, rating: rating)
            return true
        } catch {
            errorKey = "workout.error.generic"
            return false
        }
    }

    func clearError() { errorKey = nil }

    static func number(_ value: Double, separator: String, maxFraction: Int = 1) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "en_US")
        formatter.usesGroupingSeparator = false
        formatter.maximumFractionDigits = maxFraction
        formatter.minimumFractionDigits = 0
        return (formatter.string(from: NSNumber(value: value)) ?? "0").replacingOccurrences(of: ".", with: separator)
    }
}

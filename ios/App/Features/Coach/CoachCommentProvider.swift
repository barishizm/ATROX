import CoachKit
import DataKit
import Foundation
import StrengthKit

/// A proactive comment (P083) and where it was written.
struct CoachComment: Equatable, Sendable {
    let text: String
    /// Written by the on-device model: the data never left the phone.
    let onDevice: Bool
}

/// Decides where proactive comments (post-workout, weekly) come from. Rules:
/// - The "Coach comments" switch in Settings turns everything off.
/// - The server (Pro) is asked only with the AI-sharing consent; without it no request is made.
/// - A free user, or a failed request, falls back to the on-device model for the post-workout comment only.
/// - Anything that fails hides the section: `nil` means "show nothing".
struct CoachCommentProvider: Sendable {
    var digest: (any CoachDigestService)?
    var consentGranted: @Sendable () async -> Bool
    var proactiveEnabled: @Sendable () -> Bool = { CoachCommentProvider.storedSwitch() }
    var onDeviceAvailable: @Sendable (String) -> Bool = { OnDeviceComment.isAvailable(language: $0) }
    var onDevice: @Sendable (WorkoutDigest, String) async -> String? = { await OnDeviceComment.generate(for: $0, language: $1) }

    /// The Settings switch; on by default.
    static func storedSwitch(_ defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: CoachPreferences.proactiveKey) as? Bool ?? true
    }

    /// Cheap check before showing a skeleton: could a post-workout comment appear at all?
    func mightCommentOnWorkout(language: String) async -> Bool {
        guard proactiveEnabled() else { return false }
        if digest != nil, await consentGranted() { return true }
        return onDeviceAvailable(language)
    }

    func mightCommentOnWeek() async -> Bool {
        guard proactiveEnabled(), digest != nil else { return false }
        return await consentGranted()
    }

    func workoutComment(_ workout: WorkoutDigest, language: String, timeZone: String = TimeZone.current.identifier) async -> CoachComment? {
        guard proactiveEnabled() else { return nil }
        if let digest, await consentGranted() {
            let request = CoachDigestRequest(.workout(workout), locale: language, timeZone: timeZone)
            if let text = try? await digest.comment(for: request) { return CoachComment(text: text, onDevice: false) }
        }
        guard onDeviceAvailable(language), let text = await onDevice(workout, language) else { return nil }
        return CoachComment(text: text, onDevice: true)
    }

    func weeklyComment(_ week: WeeklyDigest, language: String, timeZone: String = TimeZone.current.identifier) async -> CoachComment? {
        guard await mightCommentOnWeek(), let digest else { return nil }
        let request = CoachDigestRequest(.weekly(week), locale: language, timeZone: timeZone)
        guard let text = try? await digest.comment(for: request) else { return nil }
        return CoachComment(text: text, onDevice: false)
    }
}

/// Reduces a finished workout and a weekly summary to the few facts a comment is written from.
enum CoachDigestBuilder {
    static func workout(
        _ summary: WorkoutSummary, workout: WorkoutSnapshot, names: [ExerciseRef: String], recordNames: [ExerciseRef: String]? = nil
    ) -> WorkoutDigest {
        let exercises = workout.exercises.compactMap { exercise -> WorkoutDigest.Exercise? in
            let sets = exercise.sets.filter { $0.input.isCompleted && $0.input.setType != .warmup }
            guard !sets.isEmpty else { return nil }
            let top = sets.max { $0.input.weightKg < $1.input.weightKg }
            return WorkoutDigest.Exercise(
                name: names[exercise.ref] ?? "", sets: sets.count,
                topSet: top.map { "\(number($0.input.weightKg)) kg x \($0.input.reps)" }
            )
        }.filter { !$0.name.isEmpty }
        let records = summary.records.compactMap { hit -> DigestRecord? in
            guard let name = (recordNames ?? names)[hit.ref] else { return nil }
            return DigestRecord(exercise: name, kind: hit.kind.rawValue)
        }
        let previous = summary.comparison.map { comparison in
            WorkoutDigest.Previous(
                sets: max(0, summary.setCount - comparison.setDelta), volumeKg: max(0, summary.totalVolumeKg - comparison.volumeDeltaKg),
                durationMin: max(0, Int(((summary.duration - comparison.durationDelta) / 60).rounded()))
            )
        }
        return WorkoutDigest(
            durationMin: Int((summary.duration / 60).rounded()), sets: summary.setCount, volumeKg: summary.totalVolumeKg.rounded(),
            exercises: exercises, records: records, previous: previous
        )
    }

    static func weekly(_ summary: WeeklySummary, names: [String: String]) -> WeeklyDigest {
        WeeklyDigest(
            workouts: summary.workouts, goal: summary.goal, totalSets: summary.totalSets,
            volumeChangePct: summary.volumeChange.map { $0.rounded() },
            records: summary.records.compactMap { highlight in
                names[highlight.exerciseId].map { DigestRecord(exercise: $0, kind: highlight.kind.rawValue) }
            },
            overallScore: summary.overallScore.map { $0.rounded() }, overallChange: summary.overallChange.map { ($0 * 10).rounded() / 10 },
            topGroup: summary.topGroup?.rawValue, neglectedGroups: summary.neglectedGroups.map(\.rawValue)
        )
    }

    private static func number(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
    }
}

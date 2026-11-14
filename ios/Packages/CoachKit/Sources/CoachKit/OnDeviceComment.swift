import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// The on-device fallback for the post-workout comment (P083): free users get a short comment written by Apple's
/// on-device model, so their data never leaves the phone. This file holds the safety frame as pure functions (what the
/// model is told, what it is allowed to say back) and, behind `canImport`, the call itself.
public enum OnDeviceComment {
    /// Languages the on-device comment is switched on for. Turkish stays off until its output has been judged on a
    /// real device with Apple Intelligence (docs/04-AI-KOC.md §11).
    public static let enabledLanguages: Set<String> = ["en"]

    public static func isEnabled(language: String) -> Bool { enabledLanguages.contains(language) }

    /// Short and fixed: only the numbers given, no medical or diet statements, plain text.
    public static let instructions = """
        You write one short comment for a workout app, 2 sentences at most, in plain text.
        Use only the numbers in the facts. Never invent numbers or records.
        No medical, diet, supplement or drug statements. No greeting, no emoji, no lists.
        Praise only what the facts show and end with one concrete tip for next time.
        """

    /// The facts as lines of text; nothing but summary numbers and exercise names.
    public static func prompt(for digest: WorkoutDigest) -> String {
        var lines = [
            "Facts about the workout the user just finished:",
            "duration \(digest.durationMin) min, \(digest.sets) working sets, volume \(Int(digest.volumeKg.rounded())) kg.",
        ]
        if !digest.exercises.isEmpty {
            lines.append("exercises: " + digest.exercises.prefix(8).map { exercise in
                exercise.topSet.map { "\(exercise.name) (\(exercise.sets) sets, top \($0))" } ?? "\(exercise.name) (\(exercise.sets) sets)"
            }.joined(separator: "; "))
        }
        if let previous = digest.previous {
            lines.append("previous similar workout: \(previous.sets) sets, volume \(Int(previous.volumeKg.rounded())) kg, \(previous.durationMin) min.")
        }
        if !digest.records.isEmpty {
            lines.append("records: " + digest.records.prefix(5).map { "\($0.exercise) (\($0.kind))" }.joined(separator: "; "))
        }
        return lines.joined(separator: "\n")
    }

    private static let forbidden = [
        "diagnos", "injur", "pain", "medic", "doctor", "physician", "therap", "dose", "dosage", "steroid", "sarm", "supplement",
        "creatine", "protein", "calori", "kcal", "diet", "fasting", "lose weight", "fat loss",
    ]

    /// The reply, cleaned and checked; nil when it must not be shown.
    public static func sanitize(_ raw: String) -> String? {
        var text = raw.replacingOccurrences(of: "[*_#`>]+", with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "(?m)^\\s*[-•]\\s+", with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= 10, text.count <= 400 else { return nil }
        let lowered = text.lowercased()
        guard !forbidden.contains(where: { lowered.contains($0) }) else { return nil }
        // At most three sentences: the prompt asks for two, a longer answer is the model rambling.
        let sentences = text.split(whereSeparator: { ".!?".contains($0) }).count
        return sentences <= 3 ? text : nil
    }

    /// Whether the device can write the comment right now (model present, ready, language switched on).
    public static func isAvailable(language: String) -> Bool {
        #if canImport(FoundationModels)
        guard isEnabled(language: language) else { return false }
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
        #else
        return false
        #endif
    }

    /// The comment, or nil when the model is unavailable or its answer fails the safety frame.
    public static func generate(for digest: WorkoutDigest, language: String) async -> String? {
        #if canImport(FoundationModels)
        guard isAvailable(language: language) else { return nil }
        do {
            let session = LanguageModelSession(instructions: instructions)
            let response = try await session.respond(to: prompt(for: digest))
            return sanitize(response.content)
        } catch {
            return nil
        }
        #else
        return nil
        #endif
    }
}

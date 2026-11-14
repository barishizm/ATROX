#if DEBUG
import CoachKit
import Foundation

/// UI-test coach (`-uitest-fake-coach`): answers every message the same way, like the real server would for
/// "make me a 3-day program" — a tool step, a routine proposal, text — with no network.
struct ScriptedCoachService: CoachChatService {
    func stream(_ request: CoachChatRequest) -> AsyncThrowingStream<CoachEvent, any Error> {
        let proposal = CoachProposal(
            id: "uitest-proposal",
            kind: .routine,
            data: .object([
                "name": .string("Coach 3-Day Plan"),
                "days": .array(["Day A", "Day B", "Day C"].enumerated().map { index, name in
                    .object([
                        "name": .string(name),
                        "exercises": .array([
                            Self.line(["goblet-squat", "dumbbell-bench-press", "pushups"][index], "Exercise \(index + 1)")
                        ])
                    ])
                })
            ])
        )
        let events: [CoachEvent] = [
            .quota(CoachQuota(remaining: 4, dailyMessages: 5, resetAt: Date().addingTimeInterval(3600), tier: .free)),
            .toolActivity(name: "coach.tool.get_profile", status: .started),
            .toolActivity(name: "coach.tool.get_profile", status: .finished),
            .proposal(proposal),
            .textDelta("Here is a **3-day** plan:\n\n- Day A: squat\n- Day B: press\n"),
            .textDelta("- Day C: push-ups\n\nApply it if it suits you."),
            .done(threadId: request.threadId ?? UUID())
        ]
        return AsyncThrowingStream { continuation in
            let task = Task {
                for event in events {
                    try? await Task.sleep(for: .milliseconds(150))
                    if Task.isCancelled { break }
                    continuation.yield(event)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func line(_ id: String, _ name: String) -> CoachJSON {
        .object([
            "exercise_id": .string(id), "name": .string(name), "sets": .number(3), "reps_min": .number(8), "reps_max": .number(12)
        ])
    }
}

/// No server behind the UI-test coach: nothing to list or delete remotely.
struct EmptyCoachRemote: CoachRemote {
    func threads(limit: Int, before: Date?) async throws -> [CoachThread] { [] }
    func messages(threadId: UUID, limit: Int, before: Date?) async throws -> [CoachStoredMessage] { [] }
    func renameThread(id: UUID, title: String) async throws {}
    func deleteThread(id: UUID) async throws {}
    func deleteAllThreads() async throws {}
    func memory() async throws -> [CoachMemoryNote] { [] }
    func editMemory(id: UUID, note: String) async throws {}
    func deleteMemory(id: UUID) async throws {}
    func recordDecision(proposalID: String, decision: CoachProposal.Decision) async throws {}
}
#endif

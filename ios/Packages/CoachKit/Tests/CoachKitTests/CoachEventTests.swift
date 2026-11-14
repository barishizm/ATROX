import Foundation
import Testing
@testable import CoachKit

@Suite struct CoachEventTests {
    private func events(_ text: String) -> [CoachEvent] {
        Dump.frames(of: text, chunk: .max).compactMap(CoachEvent.decode)
    }

    @Test func decodesEveryEventOfARecordedTurn() throws {
        let decoded = events(Dump.turn)
        #expect(decoded.count == 8)
        guard case .quota(let quota) = decoded[0], case .proposal(let proposal) = decoded[3] else {
            Issue.record("unexpected event order")
            return
        }
        #expect(quota.remaining == 4 && quota.dailyMessages == 5 && quota.tier == .free && quota.resetAt != nil)
        #expect(proposal.kind == .routine && proposal.warnings == [CoachProposal.Warning(exerciseId: "squat", area: "knee")])
        #expect(proposal.data["name"]?.string == "3-day plan" && proposal.needsDecision)
        #expect(decoded[1] == .toolActivity(name: "coach.tool.get_recent_workouts", status: .started))
        #expect(decoded.last == .done(threadId: UUID(uuidString: Dump.thread)!))
    }

    @Test func unknownEventTypesAndKindsAreIgnoredNotFatal() {
        #expect(events("event: telepathy\ndata: {\"x\":1}\n\n").isEmpty)
        let unknownKind = events(#"event: proposal\#ndata: {"proposal":{"id":"p","kind":"future_kind","data":{}}}"# + "\n\n")
        guard case .proposal(let proposal) = unknownKind.first else {
            Issue.record("a proposal of an unknown kind should still decode")
            return
        }
        #expect(proposal.kind == .unknown)
    }

    @Test func malformedDataIsSkipped() {
        #expect(events("event: text_delta\ndata: {not json\n\n").isEmpty)
        #expect(events("event: done\ndata: {\"thread_id\":\"nope\"}\n\n").isEmpty)
    }

    @Test func memorySavedNeedsNoDecision() {
        let note = CoachProposal(id: "m", kind: .memorySaved)
        #expect(!note.needsDecision)
    }

    @Test func parsesServerTimestampsWithMicroseconds() {
        #expect(CoachDates.parse("2026-11-14T10:00:00.123456+00:00") != nil)
        #expect(CoachDates.parse("2026-11-14T10:00:00+00:00") != nil)
        #expect(CoachDates.parse("garbage") == nil)
    }
}

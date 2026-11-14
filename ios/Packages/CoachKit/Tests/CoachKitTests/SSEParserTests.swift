import Foundation
import Testing
@testable import CoachKit

/// Recorded dump of a coach turn (what `coach-chat` writes), reused by several suites.
enum Dump {
    static let thread = "11111111-1111-4111-8111-111111111111"
    static let turn = """
    event: quota
    data: {"remaining":4,"daily_messages":5,"reset_at":"2026-11-15T00:00:00.000+00:00","tier":"free"}

    event: tool_activity
    data: {"name":"coach.tool.get_recent_workouts","status":"started"}

    event: tool_activity
    data: {"name":"coach.tool.get_recent_workouts","status":"finished"}

    event: proposal
    data: {"proposal":{"id":"p-1","kind":"routine","data":{"name":"3-day plan"},"warnings":[{"exercise_id":"squat","area":"knee"}]}}

    event: text_delta
    data: {"text":"Here is "}

    event: text_delta
    data: {"text":"your plan."}

    event: usage
    data: {"prompt_tokens":120,"cached_tokens":80,"completion_tokens":30}

    event: done
    data: {"thread_id":"\(thread)"}


    """

    static func frames(of text: String, chunk: Int) -> [SSEFrame] {
        var parser = SSEParser()
        var frames: [SSEFrame] = []
        let bytes = Array(text.utf8)
        for start in stride(from: 0, to: bytes.count, by: chunk) {
            frames += parser.feed(Data(bytes[start..<min(start + chunk, bytes.count)]))
        }
        return frames
    }
}

@Suite struct SSEParserTests {
    @Test func parsesAWholeDump() {
        let frames = Dump.frames(of: Dump.turn, chunk: .max)
        #expect(frames.map(\.event) == ["quota", "tool_activity", "tool_activity", "proposal", "text_delta", "text_delta", "usage", "done"])
    }

    @Test(arguments: [1, 2, 3, 7, 16, 64])
    func chunkBoundariesDoNotChangeTheResult(chunk: Int) {
        #expect(Dump.frames(of: Dump.turn, chunk: chunk) == Dump.frames(of: Dump.turn, chunk: .max))
    }

    @Test func aMultiByteCharacterSplitAcrossChunksSurvives() {
        let text = "event: text_delta\ndata: {\"text\":\"Çalışma güçlü 💪\"}\n\n"
        let frames = Dump.frames(of: text, chunk: 1)
        #expect(frames.count == 1)
        #expect(CoachEvent.decode(frames[0]) == .textDelta("Çalışma güçlü 💪"))
    }

    @Test func handlesCRLFCommentsAndMultiLineData() {
        var parser = SSEParser()
        let frames = parser.feed(Data(": keep-alive\r\nevent: x\r\ndata: a\r\ndata: b\r\n\r\ndata: only\n\n".utf8))
        #expect(frames == [SSEFrame(event: "x", data: "a\nb"), SSEFrame(event: "message", data: "only")])
    }

    @Test func aFrameWithoutItsBlankLineIsNotDeliveredYet() {
        var parser = SSEParser()
        #expect(parser.feed(Data("event: done\ndata: {}\n".utf8)).isEmpty)
        #expect(parser.feed(Data("\n".utf8)).count == 1)
    }
}

import Foundation
import Testing
@testable import CoachKit

@Suite struct CoachMessageTests {
    @Test func codableRoundTrip() throws {
        let proposal = CoachProposal(id: "p1", kind: .routine, data: .object(["name": .string("Push/Pull")]))
        let message = CoachMessage(role: .assistant, text: "Squat 3x5", proposals: [proposal])
        let data = try JSONEncoder().encode(message)
        #expect(try JSONDecoder().decode(CoachMessage.self, from: data) == message)
    }

    @Test func olderCachedMessagesWithoutNewFieldsStillDecode() throws {
        let id = UUID()
        let json = #"{"id":"\#(id.uuidString)","role":"user","text":"hi"}"#
        let message = try JSONDecoder().decode(CoachMessage.self, from: Data(json.utf8))
        #expect(message.status == .complete && message.proposals.isEmpty)
    }
}

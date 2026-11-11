import Foundation
import Testing
@testable import CoachKit

@Suite struct CoachMessageTests {
    @Test func codableRoundTrip() throws {
        let message = CoachMessage(role: .assistant, text: "Squat 3x5")
        let data = try JSONEncoder().encode(message)
        #expect(try JSONDecoder().decode(CoachMessage.self, from: data) == message)
    }
}

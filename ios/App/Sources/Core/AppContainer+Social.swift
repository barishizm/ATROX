import DataKit
import Foundation

/// Social wiring of the composition root (P086).
extension AppContainer {
    #if DEBUG
    /// `-uitest-fake-social`: an in-memory social backend with one discoverable person to find.
    static func uiTestSocial() -> (any SocialService)? {
        guard ProcessInfo.processInfo.arguments.contains("-uitest-fake-social") else { return nil }
        let friend = SocialPerson(
            id: UUID(), username: "bob_lifts", displayName: "Bob", avatarEmoji: "🏋️", relation: .none
        )
        return FakeSocialService(people: [friend])
    }
    #else
    static func uiTestSocial() -> (any SocialService)? { nil }
    #endif

    /// The Friends screen's model; nil without a social backend.
    func makeSocialModel() -> SocialModel? {
        social.map { SocialModel(service: $0) }
    }
}

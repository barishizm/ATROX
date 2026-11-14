import DesignSystem
import SwiftUI

/// The Coach tab (P080): builds its model once and shows the conversation.
struct CoachRootView: View {
    @Environment(AppContainer.self) private var container
    @State private var model: CoachModel?
    @State private var consent: CoachConsentModel?
    @State private var unavailable = false

    var body: some View {
        Group {
            if let consent, !consent.isGranted {
                // Nothing is built or requested before the user agrees (P081).
                if consent.state == .declined {
                    EmptyState(
                        systemImage: "hand.raised", title: "coach.consent.declined.title",
                        message: "coach.consent.declined.message", actionTitle: "coach.consent.declined.action"
                    ) { consent.reconsider() }
                    .accessibilityIdentifier("coach-consent-declined")
                } else if consent.state == .needed {
                    CoachConsentView(model: consent)
                } else {
                    LoadingState()
                }
            } else if let model {
                CoachChatView(model: model)
            } else if unavailable {
                EmptyState(systemImage: "bubble.left.and.exclamationmark.bubble.right", title: "coach.unavailable.title", message: "coach.unavailable.message")
            } else {
                LoadingState()
            }
        }
        .background(DSColor.background)
        .navigationTitle("shell.tabbar.coach")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard let agreed = await container.coachConsent() else {
                unavailable = true
                return
            }
            consent = agreed
        }
        .task(id: consent?.state) {
            guard consent?.isGranted == true, model == nil else { return }
            guard let made = await container.makeCoachModel() else {
                unavailable = true
                return
            }
            model = made
            await made.start()
        }
        .accessibilityIdentifier("coach-root")
    }
}

import DesignSystem
import SwiftUI

/// The Coach tab (P080): builds its model once and shows the conversation.
struct CoachRootView: View {
    @Environment(AppContainer.self) private var container
    @State private var model: CoachModel?
    @State private var unavailable = false

    var body: some View {
        Group {
            if let model {
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
            guard model == nil else { return }
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

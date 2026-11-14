import DataKit
import DesignSystem
import SwiftUI

/// Where an invite link (`/u/<username>`) lands (P088): the person behind it and a button to send a friend request.
struct SocialInviteView: View {
    let username: String
    @Environment(AppContainer.self) private var container
    @State private var model: SocialModel?

    var body: some View {
        Group {
            if let model { content(model) } else { LoadingState() }
        }
        .background(DSColor.background)
        .navigationTitle("social.invite.title")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard model == nil, let created = container.makeSocialModel() else { return }
            model = created
            await created.loadInvite(username)
        }
        .accessibilityIdentifier("social-invite-screen")
    }

    @ViewBuilder private func content(_ model: SocialModel) -> some View {
        switch model.invite {
        case .loading: LoadingState()
        case .failed: ErrorState(message: "social.error.generic") { Task { await model.loadInvite(username) } }
        case .needsProfile:
            // Joining comes first; once the profile exists the link is resolved again.
            SocialJoinView(model: model)
                .onChange(of: model.phase) { _, phase in if phase == .on { Task { await model.loadInvite(username) } } }
        case .itsMe: message("social.invite.itsme")
        case .notFound: message("social.invite.notfound")
        case .person(let person): personCard(person, model: model)
        }
    }

    private func message(_ key: LocalizedStringKey) -> some View {
        Text(key).font(DSFont.callout).foregroundStyle(DSColor.textSecondary).multilineTextAlignment(.center)
            .padding(Spacing.lg).frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func personCard(_ person: SocialPerson, model: SocialModel) -> some View {
        VStack(spacing: Spacing.md) {
            AvatarView(emoji: person.avatarEmoji, color: person.avatarColor, size: 80)
            Text(verbatim: person.displayName).font(DSFont.title).foregroundStyle(DSColor.textPrimary)
            Text(verbatim: "@\(person.username)").font(DSFont.callout).foregroundStyle(DSColor.textSecondary)
            switch person.relation {
            case .none:
                Button("social.request") { Task { await model.sendInviteRequest(to: person) } }
                    .buttonStyle(.borderedProminent).disabled(model.isBusy)
                    .accessibilityIdentifier("social-invite-send")
            case .outgoing: Text("social.pending").font(DSFont.callout).foregroundStyle(DSColor.textSecondary)
            case .incoming:
                Button("social.accept") { Task { await model.respond(to: person, accept: true); await model.loadInvite(username) } }
                    .buttonStyle(.borderedProminent)
            case .friend: Label("social.friends.badge", systemImage: "checkmark.circle.fill").foregroundStyle(DSColor.success)
            case .blocked: EmptyView()
            }
            if let key = model.errorKey { Text(LocalizedStringKey(key)).font(DSFont.callout).foregroundStyle(DSColor.error) }
        }
        .padding(Spacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

import DataKit
import DesignSystem
import SwiftUI

extension AvatarColor {
    var color: Color {
        switch self {
        case .ember: DSColor.accent
        case .sky: .blue
        case .mint: .mint
        case .violet: .purple
        case .gold: .yellow
        case .rose: .pink
        case .slate: .gray
        }
    }
}

struct AvatarView: View {
    let emoji: String
    let color: AvatarColor
    var size: CGFloat = 44

    var body: some View {
        Text(verbatim: emoji).font(.system(size: size * 0.5))
            .frame(width: size, height: size)
            .background(color.color.opacity(0.28), in: Circle())
            .overlay(Circle().stroke(color.color.opacity(0.6), lineWidth: 1.5))
            .accessibilityHidden(true)
    }
}

struct PersonRow: View {
    let person: SocialPerson
    var showsScore = false

    var body: some View {
        HStack(spacing: Spacing.md) {
            AvatarView(emoji: person.avatarEmoji, color: person.avatarColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: person.displayName).font(DSFont.headline).foregroundStyle(DSColor.textPrimary)
                Text(verbatim: "@\(person.username)").font(DSFont.caption).foregroundStyle(DSColor.textSecondary)
            }
            Spacer()
            if showsScore, let score = person.score {
                Text(verbatim: "\(score)").font(DSFont.numericMedium).foregroundStyle(DSColor.accent)
            }
        }
        .frame(minHeight: HitTarget.minimum)
        .accessibilityElement(children: .combine)
    }
}

/// Friends root (P086): the join screen while social is off, otherwise requests and friends.
struct SocialRootView: View {
    @Environment(AppContainer.self) private var container
    @State private var model: SocialModel?
    @State private var unavailable = false

    var body: some View {
        Group {
            if let model { content(model) } else if unavailable {
                ErrorState(message: "social.unavailable") { prepare() }
            } else {
                LoadingState()
            }
        }
        .background(DSColor.background)
        .navigationTitle("social.friends.title")
        .task { prepare() }
        .accessibilityIdentifier("social-root")
    }

    private func prepare() {
        guard model == nil else { return }
        if let created = container.makeSocialModel() {
            model = created
            Task { await created.load() }
        } else {
            unavailable = true
        }
    }

    @ViewBuilder private func content(_ model: SocialModel) -> some View {
        switch model.phase {
        case .loading: LoadingState()
        case .failed: ErrorState(message: "social.error.generic") { Task { await model.load() } }
        case .off: SocialJoinView(model: model)
        case .on: SocialFriendsView(model: model)
        }
    }
}

/// Social is off: explains what joining shares and starts the profile form. Nothing is published until the user saves.
struct SocialJoinView: View {
    @Bindable var model: SocialModel
    @State private var showsForm = false

    var body: some View {
        VStack(spacing: Spacing.lg) {
            Spacer()
            Image(systemName: "person.2.fill").font(.system(size: 56)).foregroundStyle(DSColor.accent).accessibilityHidden(true)
            Text("social.off.title").font(DSFont.title).foregroundStyle(DSColor.textPrimary)
            Text("social.off.body").font(DSFont.callout).foregroundStyle(DSColor.textSecondary).multilineTextAlignment(.center)
            PrimaryButton("social.off.cta") { showsForm = true }
                .accessibilityIdentifier("social-join")
            Spacer()
        }
        .padding(Spacing.lg)
        .accessibilityIdentifier("social-off")
        .sheet(isPresented: $showsForm) { NavigationStack { SocialProfileForm(model: model, isNew: true) } }
    }
}

struct SocialFriendsView: View {
    @Bindable var model: SocialModel
    @State private var path: [SocialPerson] = []
    @State private var showsAdd = false

    var body: some View {
        List {
            if let key = model.errorKey {
                Text(LocalizedStringKey(key)).font(DSFont.callout).foregroundStyle(DSColor.error)
            }
            if model.isEmpty {
                Section { emptyState }
            } else if !model.friends.isEmpty {
                Section {
                    NavigationLink { SocialRankingView(service: model.socialService) } label: {
                        Label("social.ranking.title", systemImage: "trophy")
                    }
                    .accessibilityIdentifier("social-ranking-link")
                }
            }
            if !model.incoming.isEmpty {
                Section("social.requests.incoming") {
                    ForEach(model.incoming) { person in
                        PersonRow(person: person)
                            .swipeActions(edge: .trailing) {
                                Button("social.decline", role: .destructive) { Task { await model.respond(to: person, accept: false) } }
                            }
                            .swipeActions(edge: .leading) {
                                Button("social.accept") { Task { await model.respond(to: person, accept: true) } }.tint(DSColor.success)
                            }
                            .contextMenu {
                                Button("social.accept") { Task { await model.respond(to: person, accept: true) } }
                                Button("social.decline", role: .destructive) { Task { await model.respond(to: person, accept: false) } }
                            }
                            .accessibilityAction(named: Text("social.accept")) { Task { await model.respond(to: person, accept: true) } }
                            .accessibilityAction(named: Text("social.decline")) { Task { await model.respond(to: person, accept: false) } }
                    }
                }
                .accessibilityIdentifier("social-incoming")
            }
            if !model.outgoing.isEmpty {
                Section("social.requests.outgoing") {
                    ForEach(model.outgoing) { person in
                        HStack {
                            PersonRow(person: person)
                            Text("social.pending").font(DSFont.caption).foregroundStyle(DSColor.textSecondary)
                        }
                        .swipeActions { Button("social.cancel", role: .destructive) { Task { await model.remove(person) } } }
                    }
                }
                .accessibilityIdentifier("social-outgoing")
            }
            if !model.friends.isEmpty {
                Section("social.friends.section") {
                    ForEach(model.friends) { person in
                        NavigationLink(value: person) { PersonRow(person: person, showsScore: true) }
                    }
                }
                .accessibilityIdentifier("social-friends")
            }
        }
        .navigationDestination(for: SocialPerson.self) { FriendProfileView(model: model, person: $0) }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showsAdd = true } label: { Label("social.add", systemImage: "person.badge.plus") }
                    .accessibilityIdentifier("social-add")
            }
            ToolbarItem(placement: .secondaryAction) {
                NavigationLink { SocialSettingsView(model: model) } label: { Label("social.settings", systemImage: "gearshape") }
            }
        }
        .refreshable { await model.load() }
        .sheet(isPresented: $showsAdd) { NavigationStack { AddFriendView(model: model) } }
    }

    private var emptyState: some View {
        VStack(spacing: Spacing.sm) {
            Text("social.empty.title").font(DSFont.headline).foregroundStyle(DSColor.textPrimary)
            Text("social.empty.body").font(DSFont.callout).foregroundStyle(DSColor.textSecondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.md)
        .accessibilityIdentifier("social-empty")
    }
}

/// Create or edit the public profile: username (with live availability), display name, avatar and the two sharing
/// switches, both off until the user turns them on.
struct SocialProfileForm: View {
    @Bindable var model: SocialModel
    let isNew: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var username = ""
    @State private var displayName = ""
    @State private var emoji = "💪"
    @State private var color: AvatarColor = .ember
    @State private var discoverable = false
    @State private var sharesScore = false
    @State private var loaded = false

    private static let emojis = ["💪", "🔥", "🏋️", "🦍", "🐺", "⚡️", "🚀", "🎯", "🦁", "🥇"]

    var body: some View {
        Form {
            Section {
                HStack { Spacer(); AvatarView(emoji: emoji, color: color, size: 72); Spacer() }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack { ForEach(Self.emojis, id: \.self) { item in
                        Button { emoji = item } label: { Text(verbatim: item).font(.title2).padding(6) }
                            .background(item == emoji ? DSColor.surfaceOverlay : .clear, in: Circle())
                            .accessibilityLabel(Text(verbatim: item))
                    } }
                }
                Picker("social.form.color", selection: $color) {
                    ForEach(AvatarColor.allCases, id: \.self) { Circle().fill($0.color).frame(width: 18, height: 18).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            Section {
                TextField("social.form.username", text: $username)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .accessibilityIdentifier("social-username")
                usernameHint
                TextField("social.form.displayname", text: $displayName).accessibilityIdentifier("social-displayname")
                if !displayName.isEmpty, !SocialTextPolicy.isDisplayNameValid(displayName) {
                    Text("social.error.displayname").font(DSFont.caption).foregroundStyle(DSColor.error)
                }
            }
            Section {
                Toggle("social.form.discoverable", isOn: $discoverable).accessibilityIdentifier("social-discoverable")
                Toggle("social.form.sharescore", isOn: $sharesScore).accessibilityIdentifier("social-sharescore")
            } footer: {
                Text("social.form.footer")
            }
            if let key = model.errorKey {
                Text(LocalizedStringKey(key)).font(DSFont.callout).foregroundStyle(DSColor.error)
            }
        }
        .tint(DSColor.accent)
        .navigationTitle(isNew ? "social.form.title.new" : "social.form.title.edit")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("social.cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("social.save") {
                    Task { if await model.save(draft) { dismiss() } }
                }
                .disabled(!canSave).accessibilityIdentifier("social-save")
            }
        }
        .task {
            guard !loaded else { return }
            loaded = true
            if let profile = model.profile {
                username = profile.username
                displayName = profile.displayName
                emoji = profile.avatarEmoji
                color = profile.avatarColor
                discoverable = profile.isDiscoverable
                sharesScore = profile.sharesScore
            }
        }
        .task(id: username) {
            // Debounce: wait for a pause in typing before asking the server.
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            await model.checkUsername(username)
        }
    }

    private var draft: SocialProfile {
        SocialProfile(
            username: username, displayName: displayName.trimmingCharacters(in: .whitespacesAndNewlines),
            avatarEmoji: emoji, avatarColor: color, isDiscoverable: discoverable, sharesScore: sharesScore
        )
    }

    private var canSave: Bool {
        model.usernameStatus == .available && SocialTextPolicy.isDisplayNameValid(displayName) && !model.isBusy
    }

    @ViewBuilder private var usernameHint: some View {
        switch model.usernameStatus {
        case .idle: Text("social.username.hint").font(DSFont.caption).foregroundStyle(DSColor.textSecondary)
        case .checking: Text("social.username.checking").font(DSFont.caption).foregroundStyle(DSColor.textSecondary)
        case .available: Label("social.username.available", systemImage: "checkmark.circle.fill")
            .font(DSFont.caption).foregroundStyle(DSColor.success)
        case .taken: Label("social.error.taken", systemImage: "xmark.circle.fill").font(DSFont.caption).foregroundStyle(DSColor.error)
        case .invalid(let issue): Text(LocalizedStringKey(Self.key(issue))).font(DSFont.caption).foregroundStyle(DSColor.error)
        }
    }

    static func key(_ issue: SocialTextPolicy.UsernameIssue) -> String {
        switch issue {
        case .tooShort: "social.username.short"
        case .tooLong: "social.username.long"
        case .invalidCharacters: "social.username.chars"
        case .reserved: "social.username.reserved"
        case .inappropriate: "social.error.username"
        }
    }
}

struct AddFriendView: View {
    @Bindable var model: SocialModel
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    var body: some View {
        List {
            if let me = model.profile {
                Section {
                    ShareLink(item: Self.invitation(for: me.username)) {
                        Label("social.invite", systemImage: "link")
                    }
                    .accessibilityIdentifier("social-invite")
                }
            }
            Section {
                ForEach(model.results) { person in
                    HStack {
                        PersonRow(person: person)
                        action(for: person)
                    }
                }
                if model.searched, model.results.isEmpty {
                    Text("social.search.none").font(DSFont.callout).foregroundStyle(DSColor.textSecondary)
                        .accessibilityIdentifier("social-search-none")
                }
            } footer: {
                Text("social.search.footer")
            }
            if let key = model.errorKey {
                Text(LocalizedStringKey(key)).font(DSFont.callout).foregroundStyle(DSColor.error)
            }
        }
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: Text("social.search.prompt"))
        .textInputAutocapitalization(.never)
        .navigationTitle("social.add")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("social.close") { dismiss() } } }
        .task(id: query) {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            await model.search(query)
        }
    }

    /// The invitation text with the universal link (`/u/<username>`); without a configured link host it is text only.
    static func invitation(for username: String) -> String {
        let text = String(localized: "social.invite.text \(username)")
        guard let link = DeepLink.inviteLink(username: username) else { return text }
        return "\(text) \(link.absoluteString)"
    }

    @ViewBuilder private func action(for person: SocialPerson) -> some View {
        switch person.relation {
        case .none:
            Button("social.request") { Task { await model.sendRequest(to: person) } }
                .buttonStyle(.bordered).accessibilityIdentifier("social-request-\(person.username)")
        case .outgoing: Text("social.pending").font(DSFont.caption).foregroundStyle(DSColor.textSecondary)
        case .incoming:
            Button("social.accept") { Task { await model.respond(to: person, accept: true); await model.search(query) } }
                .buttonStyle(.bordered)
        case .friend: Text("social.friends.badge").font(DSFont.caption).foregroundStyle(DSColor.success)
        case .blocked: EmptyView()
        }
    }
}

/// A friend's profile: the score they chose to share, level and this week's workouts. Remove, block and report live
/// in the menu (App Store user-generated-content rules).
struct FriendProfileView: View {
    @Bindable var model: SocialModel
    let person: SocialPerson
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @State private var confirmsBlock = false
    @State private var showsReport = false

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.lg) {
                AvatarView(emoji: person.avatarEmoji, color: person.avatarColor, size: 88)
                VStack(spacing: 2) {
                    Text(verbatim: person.displayName).font(DSFont.title).foregroundStyle(DSColor.textPrimary)
                    Text(verbatim: "@\(person.username)").font(DSFont.callout).foregroundStyle(DSColor.textSecondary)
                }
                if let score = person.score {
                    Card {
                        VStack(spacing: Spacing.xs) {
                            Text(verbatim: "\(score)").font(DSFont.display).foregroundStyle(DSColor.textPrimary)
                            Text(verbatim: ScoreLevel(score: Double(score)).localizedName(locale: locale))
                                .font(DSFont.headline).foregroundStyle(DSColor.textSecondary)
                            if person.scoreIsProvisional { TagChip("social.provisional", systemImage: "hourglass", style: .warning) }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .accessibilityIdentifier("friend-score")
                } else {
                    Text("social.friend.noscore").font(DSFont.callout).foregroundStyle(DSColor.textSecondary)
                        .multilineTextAlignment(.center).accessibilityIdentifier("friend-noscore")
                }
                if let weekly = person.weeklyWorkouts {
                    StatTile("social.friend.weekly", value: "\(weekly)")
                }
            }
            .padding(Spacing.md)
        }
        .background(DSColor.background)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("social.remove", role: .destructive) { Task { await model.remove(person); dismiss() } }
                    Button("social.report") { showsReport = true }
                    Button("social.block", role: .destructive) { confirmsBlock = true }
                } label: { Label("social.more", systemImage: "ellipsis.circle") }
                    .accessibilityIdentifier("friend-menu")
            }
        }
        .confirmationDialog("social.block.confirm", isPresented: $confirmsBlock, titleVisibility: .visible) {
            Button("social.block", role: .destructive) { Task { await model.block(person); dismiss() } }
        } message: { Text("social.block.body") }
        .sheet(isPresented: $showsReport) { NavigationStack { ReportView(model: model, person: person) } }
    }
}

struct ReportView: View {
    @Bindable var model: SocialModel
    let person: SocialPerson
    @Environment(\.dismiss) private var dismiss
    @State private var reason: ReportReason = .inappropriateName
    @State private var note = ""
    @State private var sent = false

    var body: some View {
        Form {
            Picker("social.report.reason", selection: $reason) {
                ForEach(ReportReason.allCases, id: \.self) { Text(LocalizedStringKey("social.report.reason.\($0.rawValue)")).tag($0) }
            }
            .pickerStyle(.inline)
            Section("social.report.note") { TextField("social.report.note.hint", text: $note, axis: .vertical).lineLimit(3...6) }
            if sent { Label("social.report.sent", systemImage: "checkmark.circle.fill").foregroundStyle(DSColor.success) }
            if let key = model.errorKey { Text(LocalizedStringKey(key)).foregroundStyle(DSColor.error) }
        }
        .navigationTitle("social.report")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("social.close") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("social.report.send") {
                    Task {
                        if await model.report(person, reason: reason, note: String(note.prefix(500))) {
                            sent = true
                            try? await Task.sleep(for: .seconds(1))
                            dismiss()
                        }
                    }
                }
                .disabled(sent || model.isBusy)
            }
        }
    }
}

/// Visibility, blocked users and "turn social off".
struct SocialSettingsView: View {
    @Bindable var model: SocialModel
    @State private var confirmsOff = false
    @State private var editing = false

    var body: some View {
        List {
            if let profile = model.profile {
                Section {
                    HStack(spacing: Spacing.md) {
                        AvatarView(emoji: profile.avatarEmoji, color: profile.avatarColor)
                        VStack(alignment: .leading) {
                            Text(verbatim: profile.displayName).font(DSFont.headline)
                            Text(verbatim: "@\(profile.username)").font(DSFont.caption).foregroundStyle(DSColor.textSecondary)
                        }
                    }
                    Button("social.edit") { editing = true }.accessibilityIdentifier("social-edit")
                    LabeledContent("social.form.discoverable") { Text(LocalizedStringKey(profile.isDiscoverable ? "social.state.on" : "social.state.off")) }
                    LabeledContent("social.form.sharescore") { Text(LocalizedStringKey(profile.sharesScore ? "social.state.on" : "social.state.off")) }
                }
            }
            Section("social.blocked.title") {
                if model.blocked.isEmpty {
                    Text("social.blocked.none").foregroundStyle(DSColor.textSecondary)
                }
                ForEach(model.blocked) { person in
                    HStack {
                        PersonRow(person: person)
                        Button("social.unblock") { Task { await model.unblock(person) } }.buttonStyle(.bordered)
                    }
                }
            }
            Section {
                Button("social.turnoff", role: .destructive) { confirmsOff = true }.accessibilityIdentifier("social-turnoff")
            } footer: { Text("social.turnoff.footer") }
        }
        .navigationTitle("social.settings")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $editing) { NavigationStack { SocialProfileForm(model: model, isNew: false) } }
        .confirmationDialog("social.turnoff.confirm", isPresented: $confirmsOff, titleVisibility: .visible) {
            Button("social.turnoff", role: .destructive) { Task { await model.turnOff() } }
        } message: { Text("social.turnoff.body") }
    }
}

import CoachKit
import DesignSystem
import SwiftUI

/// The conversation: messages, tool activity, cards, the composer with its quota meter, and the failure states.
struct CoachChatView: View {
    @Bindable var model: CoachModel
    @Environment(AppContainer.self) private var container
    @Environment(\.locale) private var locale
    @State private var showsThreads = false
    @State private var showsPaywall = false
    @FocusState private var inputFocused: Bool

    private var session: CoachSession { model.session }

    var body: some View {
        VStack(spacing: 0) {
            if !model.isOnline { offlineBanner }
            messages
            bottomArea
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { showsThreads = true } label: { Image(systemName: "clock.arrow.circlepath") }
                    .accessibilityLabel(Text("coach.threads.title")).accessibilityIdentifier("coach-threads")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { model.newConversation() } label: { Image(systemName: "square.and.pencil") }
                    .accessibilityLabel(Text("coach.new")).accessibilityIdentifier("coach-new")
            }
        }
        .sheet(isPresented: $showsThreads) {
            NavigationStack { CoachThreadsView(model: model) { showsThreads = false } }
        }
        .sheet(isPresented: $showsPaywall) { NavigationStack { PaywallView(feature: .coachUnlimited) } }
        .task { await model.watchConnectivity() }
        .onChange(of: container.pendingCoachPrompt, initial: true) { _, prompt in
            guard let prompt else { return }
            model.draft = prompt
            container.pendingCoachPrompt = nil
            inputFocused = true
        }
    }

    // MARK: Messages

    @ViewBuilder
    private var messages: some View {
        if session.messages.isEmpty {
            ScrollView { emptyConversation.padding(Spacing.md) }
                .scrollDismissesKeyboard(.interactively)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: Spacing.md) {
                        ForEach(session.messages) { message in
                            CoachMessageRow(message: message, model: model, activityKey: activityKey(for: message))
                                .id(message.id)
                        }
                        Color.clear.frame(height: 1).id("coach-bottom")
                    }
                    .padding(Spacing.md)
                }
                .scrollDismissesKeyboard(.interactively)
                .defaultScrollAnchor(.bottom)
                .onChange(of: session.messages.last?.text) { proxy.scrollTo("coach-bottom", anchor: .bottom) }
                .onChange(of: session.messages.count) { withAnimation { proxy.scrollTo("coach-bottom", anchor: .bottom) } }
            }
        }
    }

    private func activityKey(for message: CoachMessage) -> String? {
        guard message.id == session.messages.last?.id, case .streaming(let key) = session.state else { return nil }
        return key
    }

    private var emptyConversation: some View {
        VStack(spacing: Spacing.lg) {
            EmptyState(systemImage: "bubble.left.and.text.bubble.right", title: "coach.empty.title", message: "coach.empty.message")
            VStack(spacing: Spacing.sm) {
                ForEach(model.suggestions, id: \.self) { suggestion in
                    Button { model.ask(suggestion) } label: {
                        HStack {
                            Text(verbatim: suggestion).font(DSFont.callout).foregroundStyle(DSColor.textPrimary).multilineTextAlignment(.leading)
                            Spacer(minLength: Spacing.sm)
                            Image(systemName: "arrow.up.circle").foregroundStyle(DSColor.accent)
                        }
                        .padding(Spacing.md)
                        .frame(maxWidth: .infinity, minHeight: HitTarget.minimum)
                        .background(DSColor.surface, in: RoundedRectangle(cornerRadius: Radius.md))
                    }
                    .buttonStyle(.plain)
                    .disabled(!model.isOnline)
                    .accessibilityIdentifier("coach-suggestion")
                }
            }
        }
    }

    // MARK: Bottom area

    private var bottomArea: some View {
        VStack(spacing: Spacing.sm) {
            if let banner = model.banner { bannerView(banner) }
            if case .failed(let error) = session.state { failure(error) }
            if model.quotaExhausted { quotaExhausted } else { composer }
        }
        .padding(.horizontal, Spacing.md).padding(.vertical, Spacing.sm)
        .background(DSColor.background)
    }

    private var offlineBanner: some View {
        Label("coach.offline", systemImage: "wifi.slash")
            .font(DSFont.callout).foregroundStyle(DSColor.warning)
            .frame(maxWidth: .infinity).padding(Spacing.sm)
            .background(DSColor.surface)
            .accessibilityIdentifier("coach-offline")
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(alignment: .bottom, spacing: Spacing.sm) {
                TextField("coach.input.placeholder", text: $model.draft, axis: .vertical)
                    .lineLimit(1...5)
                    .focused($inputFocused)
                    .padding(.horizontal, Spacing.md).padding(.vertical, Spacing.sm)
                    .background(DSColor.surface, in: RoundedRectangle(cornerRadius: Radius.lg))
                    .accessibilityIdentifier("coach-input")
                if session.isBusy {
                    Button { model.stop() } label: { Image(systemName: "stop.circle.fill").font(.system(size: 34)) }
                        .foregroundStyle(DSColor.accent).frame(minWidth: HitTarget.minimum, minHeight: HitTarget.minimum)
                        .accessibilityLabel(Text("coach.stop")).accessibilityIdentifier("coach-stop")
                } else {
                    Button { model.send() } label: { Image(systemName: "arrow.up.circle.fill").font(.system(size: 34)) }
                        .foregroundStyle(model.canSend ? DSColor.accent : DSColor.textTertiary)
                        .frame(minWidth: HitTarget.minimum, minHeight: HitTarget.minimum)
                        .disabled(!model.canSend)
                        .accessibilityLabel(Text("coach.send")).accessibilityIdentifier("coach-send")
                }
            }
            HStack {
                if let quota = session.quota {
                    Text("coach.quota.remaining \(quota.remaining) \(quota.dailyMessages)")
                        .accessibilityIdentifier("coach-quota")
                }
                Spacer()
                if model.characterCount >= CoachSession.maxMessageLength - 300 {
                    Text(verbatim: "\(model.characterCount)/\(CoachSession.maxMessageLength)")
                        .foregroundStyle(model.isOverLimit ? DSColor.error : DSColor.textTertiary)
                        .accessibilityIdentifier("coach-counter")
                }
            }
            .font(DSFont.caption).foregroundStyle(DSColor.textTertiary)
        }
    }

    /// The day's messages are used up: when it resets, and (free tier) what Pro adds.
    private var quotaExhausted: some View {
        Card {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Label("coach.quota.exhausted.title", systemImage: "hourglass").font(DSFont.headline)
                if let reset = resetDate {
                    Text("coach.quota.exhausted.reset \(reset.formatted(date: .omitted, time: .shortened))")
                        .font(DSFont.callout).foregroundStyle(DSColor.textSecondary)
                }
                if isFree {
                    Button { showsPaywall = true } label: { Text("coach.quota.upgrade").frame(maxWidth: .infinity, minHeight: HitTarget.minimum - Spacing.sm) }
                        .buttonStyle(.borderedProminent).tint(DSColor.accent).accessibilityIdentifier("coach-upgrade")
                }
            }
        }
        .accessibilityIdentifier("coach-quota-exhausted")
    }

    private var resetDate: Date? {
        if case .failed(.quotaExceeded(let reset, _)) = session.state { return reset ?? session.quota?.resetAt }
        return session.quota?.resetAt
    }

    private var isFree: Bool {
        if case .failed(.quotaExceeded(_, let upgrade)) = session.state { return upgrade }
        return session.quota?.tier != .pro
    }

    // MARK: Banners and failures

    @ViewBuilder
    private func bannerView(_ banner: CoachModel.Banner) -> some View {
        HStack(spacing: Spacing.sm) {
            switch banner {
            case .applied(let routineId):
                Label("coach.banner.applied", systemImage: "checkmark.circle.fill").foregroundStyle(DSColor.success)
                Spacer()
                if let routineId {
                    Button("coach.banner.open") {
                        model.banner = nil
                        container.requestedRoutine = routineId
                    }
                    .accessibilityIdentifier("coach-open-program")
                }
            case .applyFailed:
                Label("coach.banner.failed", systemImage: "exclamationmark.triangle.fill").foregroundStyle(DSColor.warning)
                Spacer()
            case .memoryRemoved:
                Label("coach.banner.memoryRemoved", systemImage: "trash").foregroundStyle(DSColor.textSecondary)
                Spacer()
            }
            Button { model.banner = nil } label: { Image(systemName: "xmark") }
                .foregroundStyle(DSColor.textTertiary).accessibilityLabel(Text("coach.banner.dismiss"))
        }
        .font(DSFont.callout)
        .padding(Spacing.sm)
        .background(DSColor.surface, in: RoundedRectangle(cornerRadius: Radius.md))
        .accessibilityIdentifier("coach-banner")
    }

    @ViewBuilder
    private func failure(_ error: CoachError) -> some View {
        if case .quotaExceeded = error {
            EmptyView()
        } else {
            HStack(alignment: .top, spacing: Spacing.sm) {
                Image(systemName: "exclamationmark.circle.fill").foregroundStyle(DSColor.error).accessibilityHidden(true)
                Text(Self.message(for: error)).font(DSFont.callout).foregroundStyle(DSColor.textPrimary)
                Spacer(minLength: 0)
                if error.isRetryable {
                    Button("coach.retry") { model.retry() }.buttonStyle(.bordered).accessibilityIdentifier("coach-retry")
                }
            }
            .padding(Spacing.sm)
            .background(DSColor.surface, in: RoundedRectangle(cornerRadius: Radius.md))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("coach-error")
        }
    }

    static func message(for error: CoachError) -> LocalizedStringKey {
        switch error {
        case .consentRequired: "coach.error.consent"
        case .rateLimited: "coach.error.rateLimited"
        case .duplicateMessage: "coach.error.duplicate"
        case .unavailable: "coach.error.unavailable"
        case .unauthorized: "coach.error.unauthorized"
        case .offline: "coach.error.offline"
        case .timeout: "coach.error.timeout"
        case .quotaExceeded, .cancelled, .invalidResponse, .server: "coach.error.generic"
        }
    }
}

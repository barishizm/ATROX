import CoachKit
import DesignSystem
import SwiftUI

/// One bubble: the user's message on the right, the coach's answer (Markdown, copy, proposal cards) on the left.
struct CoachMessageRow: View {
    let message: CoachMessage
    let model: CoachModel
    let activityKey: String?
    @Environment(\.locale) private var locale

    var body: some View {
        switch message.role {
        case .user: userBubble
        case .assistant: assistant
        }
    }

    private var userBubble: some View {
        HStack {
            Spacer(minLength: Spacing.xl)
            Text(verbatim: message.text)
                .font(DSFont.body).foregroundStyle(DSColor.onAccent)
                .padding(.horizontal, Spacing.md).padding(.vertical, Spacing.sm)
                .background(DSColor.accent, in: RoundedRectangle(cornerRadius: Radius.lg))
                .textSelection(.enabled)
        }
        .accessibilityIdentifier("coach-user-message")
    }

    private var assistant: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            if message.status == .streaming && message.text.isEmpty {
                activity
            } else if !message.text.isEmpty {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    MarkdownTextView(text: message.text)
                        .foregroundStyle(DSColor.textPrimary)
                        .padding(.horizontal, Spacing.md).padding(.vertical, Spacing.sm)
                        .background(DSColor.surface, in: RoundedRectangle(cornerRadius: Radius.lg))
                        .textSelection(.enabled)
                    if message.status == .partial { partialNote }
                    if message.status == .complete { copyButton }
                }
                .accessibilityIdentifier("coach-answer")
            }
            ForEach(message.proposals) { proposal in
                ProposalCardView(proposal: proposal, model: model)
            }
            if message.status == .streaming && !message.text.isEmpty, let activityKey { activityLine(activityKey) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var activity: some View {
        if let activityKey {
            activityLine(activityKey)
        } else {
            TypingIndicator().accessibilityIdentifier("coach-typing")
        }
    }

    private func activityLine(_ key: String) -> some View {
        HStack(spacing: Spacing.sm) {
            ProgressView().controlSize(.small)
            Text(verbatim: Self.activityText(key, locale: locale)).font(DSFont.callout).foregroundStyle(DSColor.textSecondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("coach-activity")
    }

    private var partialNote: some View {
        Label("coach.message.partial", systemImage: "scissors")
            .font(DSFont.footnote).foregroundStyle(DSColor.textTertiary)
    }

    private var copyButton: some View {
        Button {
            UIPasteboard.general.string = message.text
        } label: {
            Label("coach.message.copy", systemImage: "doc.on.doc").font(DSFont.footnote)
        }
        .foregroundStyle(DSColor.textTertiary)
        .frame(minHeight: HitTarget.minimum, alignment: .leading)
        .accessibilityIdentifier("coach-copy")
    }

    /// "Looking at your workout history…" for `coach.tool.<name>`; unknown tools get a generic line.
    static func activityText(_ key: String, locale: Locale) -> String {
        let text = LocalizedText.string(key, locale: locale, arguments: [])
        return text == key ? LocalizedText.string("coach.tool.generic", locale: locale, arguments: []) : text
    }
}

/// Three pulsing dots while the coach has not written anything yet.
struct TypingIndicator: View {
    @State private var phase = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: Spacing.xs) {
            ForEach(0..<3, id: \.self) { index in
                Circle().fill(DSColor.textTertiary).frame(width: 8, height: 8)
                    .opacity(reduceMotion || phase ? 1 : 0.3)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.6).repeatForever().delay(Double(index) * 0.2), value: phase)
            }
        }
        .padding(.horizontal, Spacing.md).padding(.vertical, Spacing.sm)
        .background(DSColor.surface, in: Capsule())
        .onAppear { phase = true }
        .accessibilityLabel(Text("coach.typing"))
    }
}

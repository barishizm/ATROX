import CoachKit
import DesignSystem
import SwiftUI

/// A proposal as a card under the coach's answer: what would change, then Apply / Edit / Reject (P080). A memory note
/// the coach already saved shows what it noted, with Undo.
struct ProposalCardView: View {
    let proposal: CoachProposal
    let model: CoachModel
    @Environment(\.locale) private var locale
    @State private var isWorking = false
    @State private var showsPreview = false

    private var summary: ProposalSummary { ProposalSummary.make(for: proposal, locale: locale) }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                header
                if !summary.lines.isEmpty { lines }
                ForEach(summary.warnings, id: \.self) { warning in
                    Label { Text(verbatim: warning).font(DSFont.footnote) } icon: { Image(systemName: "exclamationmark.triangle.fill") }
                        .foregroundStyle(DSColor.warning)
                }
                footer
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(proposal.kind == .memorySaved ? "coach-memory-card" : "proposal-card")
        .sheet(isPresented: $showsPreview) { RoutinePreviewView(summary: summary) }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            Image(systemName: icon).foregroundStyle(DSColor.accent).frame(width: 24).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(verbatim: summary.title).font(DSFont.headline).foregroundStyle(DSColor.textPrimary)
                if let subtitle = summary.subtitle {
                    Text(verbatim: subtitle).font(DSFont.callout).foregroundStyle(DSColor.textSecondary)
                }
            }
        }
    }

    private var lines: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            ForEach(Array(summary.lines.prefix(6).enumerated()), id: \.offset) { _, line in
                Text(verbatim: line).font(DSFont.callout).foregroundStyle(DSColor.textPrimary)
            }
            if summary.lines.count > 6 {
                Text("coach.proposal.more \(summary.lines.count - 6)").font(DSFont.footnote).foregroundStyle(DSColor.textTertiary)
            }
        }
    }

    @ViewBuilder
    private var footer: some View {
        if let decision = proposal.decision {
            Label(decisionText(decision), systemImage: decision == .rejected || decision == .undone ? "xmark.circle" : "checkmark.circle.fill")
                .font(DSFont.footnote.weight(.semibold))
                .foregroundStyle(decision == .rejected || decision == .undone ? DSColor.textTertiary : DSColor.success)
                .accessibilityIdentifier("proposal-decision")
        } else if proposal.kind == .memorySaved {
            Button { run { await model.undoMemory(proposal) } } label: { Text("coach.proposal.memory.undo") }
                .buttonStyle(.bordered).disabled(isWorking).accessibilityIdentifier("coach-memory-undo")
        } else if proposal.kind != .unknown {
            actions
        }
    }

    private var actions: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            if proposal.kind == .routine {
                Button { showsPreview = true } label: { Label("coach.proposal.preview", systemImage: "list.bullet.rectangle") }
                    .font(DSFont.callout).accessibilityIdentifier("proposal-preview")
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Spacing.sm) { buttons }
                VStack(spacing: Spacing.sm) { buttons }
            }
        }
    }

    @ViewBuilder
    private var buttons: some View {
        Button { run { await model.apply(proposal) } } label: { Text("coach.proposal.apply").frame(maxWidth: .infinity, minHeight: HitTarget.minimum - Spacing.sm) }
            .buttonStyle(.borderedProminent).tint(DSColor.accent).disabled(isWorking)
            .accessibilityIdentifier("proposal-apply")
        if proposal.kind != .goalUpdate {
            Button { run { await model.apply(proposal, thenEdit: true) } } label: { Text("coach.proposal.edit").frame(maxWidth: .infinity, minHeight: HitTarget.minimum - Spacing.sm) }
                .buttonStyle(.bordered).disabled(isWorking)
                .accessibilityIdentifier("proposal-edit")
        }
        Button(role: .destructive) { model.reject(proposal) } label: { Text("coach.proposal.reject").frame(maxWidth: .infinity, minHeight: HitTarget.minimum - Spacing.sm) }
            .buttonStyle(.bordered).disabled(isWorking)
            .accessibilityIdentifier("proposal-reject")
    }

    private func run(_ work: @escaping @MainActor () async -> Void) {
        isWorking = true
        Task {
            await work()
            isWorking = false
        }
    }

    private func decisionText(_ decision: CoachProposal.Decision) -> LocalizedStringKey {
        switch decision {
        case .applied: "coach.proposal.decision.applied"
        case .edited: "coach.proposal.decision.edited"
        case .rejected: "coach.proposal.decision.rejected"
        case .undone: "coach.proposal.decision.undone"
        }
    }

    private var icon: String {
        switch proposal.kind {
        case .routine: "calendar.badge.plus"
        case .routineEdit: "slider.horizontal.3"
        case .exerciseSwap: "arrow.left.arrow.right"
        case .goalUpdate: "target"
        case .memorySaved: "brain.head.profile"
        case .unknown: "questionmark.circle"
        }
    }
}

/// The whole proposed routine, day by day, before the user decides.
struct RoutinePreviewView: View {
    let summary: ProposalSummary
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(summary.days) { day in
                    Section(day.name) {
                        ForEach(Array(day.lines.enumerated()), id: \.offset) { _, line in Text(verbatim: line) }
                    }
                }
            }
            .navigationTitle(Text(verbatim: summary.title))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("coach.preview.close") { dismiss() } }
            }
        }
        .accessibilityIdentifier("routine-preview")
    }
}

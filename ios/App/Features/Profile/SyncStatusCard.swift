import DataKit
import DesignSystem
import SwiftUI

/// Profile card: last sync time, waiting changes, errors and "Sync now" (P045).
struct SyncStatusCard: View {
    let sync: SyncCoordinator
    @Environment(\.locale) private var locale

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack(spacing: Spacing.md) {
                    Image(systemName: icon).foregroundStyle(color).frame(width: 28).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        headline.font(DSFont.body).foregroundStyle(DSColor.textPrimary)
                        lastSynced.font(DSFont.footnote).foregroundStyle(DSColor.textSecondary)
                    }
                    Spacer(minLength: Spacing.sm)
                    if SyncStatusPresenter.canSyncNow(phase: sync.phase) {
                        Button("sync.action.now") { sync.request(.manual) }
                            .font(DSFont.callout)
                            .accessibilityIdentifier("profile-sync-now")
                    } else {
                        ProgressView()
                    }
                }
                if sync.failedCount > 0 {
                    Text("sync.status.failedRows \(sync.failedCount)").font(DSFont.footnote).foregroundStyle(DSColor.error)
                }
            }
            .frame(minHeight: HitTarget.minimum)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("profile-sync-status")
    }

    @ViewBuilder private var headline: some View {
        switch SyncStatusPresenter.headline(phase: sync.phase, pending: sync.pendingCount) {
        case .syncing: Text("sync.status.syncing")
        case .restoring(let done, let total): Text("sync.restore.detail \(done) \(total)")
        case .upToDate: Text("sync.status.upToDate")
        case .pending(let count): Text("sync.status.pending \(count)")
        case .offline: Text("sync.status.offline")
        case .failed: Text("sync.status.failed")
        }
    }

    @ViewBuilder private var lastSynced: some View {
        if let date = sync.lastSyncedAt {
            Text("sync.status.lastSynced \(date.formatted(.relative(presentation: .named).locale(locale)))")
        } else {
            Text("sync.status.never")
        }
    }

    private var icon: String {
        switch SyncStatusPresenter.tone(phase: sync.phase, failedRows: sync.failedCount) {
        case .normal: "arrow.triangle.2.circlepath.icloud"
        case .warning: "icloud.slash"
        case .error: "exclamationmark.icloud"
        }
    }

    private var color: Color {
        switch SyncStatusPresenter.tone(phase: sync.phase, failedRows: sync.failedCount) {
        case .normal: DSColor.accent
        case .warning: DSColor.textSecondary
        case .error: DSColor.error
        }
    }
}

/// Full-screen progress while the first sign-in downloads the user's data (P045).
struct RestoreProgressView: View {
    let progress: SyncProgress

    var body: some View {
        VStack(spacing: Spacing.md) {
            Text("sync.restore.title").font(DSFont.title).foregroundStyle(DSColor.textPrimary)
            ProgressView(value: progress.fraction).frame(maxWidth: 280)
            if progress.total > 0 {
                Text("sync.restore.detail \(progress.done) \(progress.total)")
                    .font(DSFont.footnote).foregroundStyle(DSColor.textSecondary).monospacedDigit()
            }
        }
        .padding(Spacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DSColor.background)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("sync-restore-progress")
    }
}

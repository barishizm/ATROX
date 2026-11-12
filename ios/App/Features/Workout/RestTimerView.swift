import DataKit
import DesignSystem
import SwiftUI

/// Rest countdown strip above the keypad: a ring with the remaining time, −15 / +15 and skip.
struct RestTimerView: View {
    let timer: RestTimerController

    var body: some View {
        if timer.isRunning {
            HStack(spacing: Spacing.md) {
                TimelineView(.animation(minimumInterval: 0.25)) { context in
                    ring(at: context.date)
                }
                Spacer(minLength: 0)
                stepButton(-RestTimerController.adjustStep, label: "−15", id: "rest-minus")
                stepButton(RestTimerController.adjustStep, label: "+15", id: "rest-plus")
                Button { Task { await timer.skip() } } label: {
                    Text("workout.rest.skip").font(DSFont.headline).foregroundStyle(DSColor.onAccent)
                        .padding(.horizontal, Spacing.md)
                        .frame(minHeight: HitTarget.button)
                        .background(DSColor.accent, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("rest-skip")
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .background(.bar)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("rest-timer")
        }
    }

    private func ring(at date: Date) -> some View {
        let remaining = timer.remaining(at: date)
        return ZStack {
            Circle().stroke(DSColor.surfaceRaised, lineWidth: 6)
            Circle()
                .trim(from: 0, to: timer.fraction(at: date))
                .stroke(DSColor.accent, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(verbatim: ActiveWorkoutFormat.clock(remaining.rounded(.up)))
                .font(DSFont.numericSmall)
        }
        .frame(width: 64, height: 64)
        .task(id: timer.run?.endsAt) { await tickUntilDue() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("workout.rest.title")
        .accessibilityValue(ActiveWorkoutFormat.clock(remaining.rounded(.up)))
        .accessibilityIdentifier("rest-ring")
    }

    private func stepButton(_ seconds: TimeInterval, label: String, id: String) -> some View {
        Button { Task { await timer.adjust(by: seconds) } } label: {
            Text(verbatim: label).font(DSFont.headline)
                .frame(minWidth: HitTarget.button, minHeight: HitTarget.button)
                .background(DSColor.surfaceRaised, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }

    /// Backup for the controller's own waiter: makes sure the ring settles when the time is up.
    private func tickUntilDue() async {
        while timer.isRunning, timer.remaining() > 0 {
            try? await Task.sleep(for: .milliseconds(250))
        }
        await timer.finishIfDue()
    }
}

/// Explanation shown once, before the system asks for notification permission.
struct RestNotificationPrimerView: View {
    let timer: RestTimerController

    var body: some View {
        VStack(spacing: Spacing.lg) {
            Image(systemName: "bell.badge.fill").font(.system(size: 56)).foregroundStyle(DSColor.accent)
                .accessibilityHidden(true)
            Text("workout.rest.primer.title").font(DSFont.title).multilineTextAlignment(.center)
            Text("workout.rest.primer.body").font(DSFont.body).foregroundStyle(DSColor.textSecondary)
                .multilineTextAlignment(.center)
            Button { Task { await timer.acceptPrimer() } } label: {
                Text("workout.rest.primer.allow").font(DSFont.headline).foregroundStyle(DSColor.onAccent)
                    .frame(maxWidth: .infinity, minHeight: HitTarget.button)
                    .background(DSColor.accent, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("rest-primer-allow")
            Button("workout.rest.primer.later") { timer.declinePrimer() }
                .accessibilityIdentifier("rest-primer-later")
        }
        .padding(Spacing.lg)
        .presentationDetents([.medium])
    }
}

import DesignSystem
import SwiftUI

/// First-open AI data sharing consent (P081). Nothing is requested from the network before "Kabul ediyorum";
/// there is no pre-ticked box. Wording changes need a new `ConsentVersions.aiSharing` and a legal review
/// (docs/YAYIN-KONTROL.md).
struct CoachConsentView: View {
    let model: CoachConsentModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Image(systemName: "hand.raised.fill").font(.largeTitle).foregroundStyle(DSColor.accent)
                    Text("coach.consent.title").font(DSFont.title)
                    Text("coach.consent.intro").font(DSFont.body).foregroundStyle(DSColor.textSecondary)
                }
                block("coach.consent.sent.title", lines: [
                    "coach.consent.sent.profile", "coach.consent.sent.scores",
                    "coach.consent.sent.history", "coach.consent.sent.messages",
                ])
                block("coach.consent.recipient.title", lines: ["coach.consent.recipient.body"])
                block("coach.consent.purpose.title", lines: ["coach.consent.purpose.body"])
                block("coach.consent.notsent.title", lines: ["coach.consent.notsent.body"])
                Text("coach.consent.withdraw").font(DSFont.footnote).foregroundStyle(DSColor.textSecondary)
                if model.failed {
                    Text("coach.consent.failed").font(DSFont.footnote).foregroundStyle(DSColor.error)
                }
                VStack(spacing: Spacing.sm) {
                    Button { Task { await model.accept() } } label: {
                        Text("coach.consent.accept").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent).controlSize(.large)
                    .accessibilityIdentifier("coach-consent-accept")
                    Button { Task { await model.decline() } } label: {
                        Text("coach.consent.decline").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered).controlSize(.large)
                    .accessibilityIdentifier("coach-consent-decline")
                }
            }
            .padding(Spacing.md)
        }
        .accessibilityIdentifier("coach-consent")
    }

    private func block(_ title: LocalizedStringKey, lines: [LocalizedStringKey]) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(title).font(DSFont.headline)
            ForEach(lines.indices, id: \.self) { index in
                Label { Text(lines[index]).font(DSFont.callout) } icon: {
                    Image(systemName: "circle.fill").font(.system(size: 5)).foregroundStyle(DSColor.textSecondary)
                }
            }
        }
    }
}

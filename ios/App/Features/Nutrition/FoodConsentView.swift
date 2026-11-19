import DesignSystem
import SwiftUI

/// Consent for sending meal photos and descriptions to the AI provider (App Store 5.1.2(i)). Nothing is requested before
/// "I agree"; wording changes need a new `ConsentVersions.foodAISharing` (and the same value on the server).
struct FoodConsentView: View {
    let model: FoodConsentModel
    var onFinish: () -> Void = {}

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Image(systemName: "camera.viewfinder").font(.largeTitle).foregroundStyle(DSColor.accent).accessibilityHidden(true)
                    Text("food.consent.title").font(DSFont.title)
                    Text("food.consent.intro").font(DSFont.body).foregroundStyle(DSColor.textSecondary)
                }
                block("food.consent.sent.title", lines: ["food.consent.sent.photo", "food.consent.sent.text", "food.consent.sent.locale", "food.consent.sent.coach"])
                block("food.consent.recipient.title", lines: ["food.consent.recipient.body"])
                block("food.consent.notsent.title", lines: ["food.consent.notsent.body"])
                block("food.consent.barcode.title", lines: ["food.consent.barcode.body"])
                Text("food.consent.withdraw").font(DSFont.footnote).foregroundStyle(DSColor.textSecondary)
                if model.failed { Text("coach.consent.failed").font(DSFont.footnote).foregroundStyle(DSColor.error) }
                VStack(spacing: Spacing.sm) {
                    Button { Task { await model.accept(); onFinish() } } label: { Text("food.consent.accept").frame(maxWidth: .infinity) }
                        .buttonStyle(.borderedProminent).tint(DSColor.accentFill).controlSize(.large)
                        .accessibilityIdentifier("food-consent-accept")
                    Button { Task { await model.decline(); onFinish() } } label: { Text("food.consent.decline").frame(maxWidth: .infinity) }
                        .buttonStyle(.bordered).controlSize(.large)
                        .accessibilityIdentifier("food-consent-decline")
                }
            }
            .padding(Spacing.md)
        }
        .background(DSColor.background)
        .accessibilityIdentifier("food-consent")
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

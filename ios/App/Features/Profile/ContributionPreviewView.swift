import DataKit
import DesignSystem
import SwiftUI

/// "What was shared last month?" (P093): the monthly summary exactly as it is sent, in readable form.
struct ContributionPreviewView: View {
    let model: ProfileModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.md) {
                Text("contribution.preview.intro")
                    .font(DSFont.callout)
                    .foregroundStyle(DSColor.textSecondary)
                if let preview = model.contributionPreview {
                    Text(preview.wasSent ? "contribution.preview.sent" : "contribution.preview.next")
                        .font(DSFont.headline)
                        .foregroundStyle(DSColor.textPrimary)
                        .accessibilityAddTraits(.isHeader)
                    Card {
                        Text(verbatim: preview.payload.readableJSON())
                            .font(.system(.footnote, design: .monospaced))
                            .foregroundStyle(DSColor.textPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .accessibilityIdentifier("contribution-preview-payload")
                    Text("contribution.preview.noIdentity")
                        .font(DSFont.footnote)
                        .foregroundStyle(DSColor.textSecondary)
                } else if model.contributionPreviewLoaded {
                    Text("contribution.preview.empty")
                        .font(DSFont.callout)
                        .foregroundStyle(DSColor.textSecondary)
                        .accessibilityIdentifier("contribution-preview-empty")
                } else {
                    ProgressView()
                }
            }
            .padding(Spacing.md)
        }
        .background(DSColor.background)
        .navigationTitle("settings.contribution.preview")
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.loadContributionPreview() }
        .accessibilityIdentifier("contribution-preview")
    }
}

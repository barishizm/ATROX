import DataKit
import DesignSystem
import SwiftUI

/// One insight: icon, title, body, one action and (optionally) a dismiss button.
struct InsightCardView: View {
    let item: InsightItem
    var onAction: () -> Void
    var onDismiss: (() -> Void)?

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack(alignment: .top, spacing: Spacing.sm) {
                    Image(systemName: item.icon).foregroundStyle(DSColor.accent).frame(width: 28).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text(verbatim: item.title).font(DSFont.headline).foregroundStyle(DSColor.textPrimary)
                        Text(verbatim: item.body).font(DSFont.callout).foregroundStyle(DSColor.textSecondary)
                    }
                    Spacer(minLength: 0)
                    if let onDismiss {
                        Button(action: onDismiss) {
                            Image(systemName: "xmark").font(DSFont.caption).foregroundStyle(DSColor.textTertiary)
                                .frame(width: HitTarget.minimum, height: HitTarget.minimum)
                        }
                        .accessibilityLabel(Text("insight.dismiss"))
                        .accessibilityIdentifier("insight-dismiss")
                    }
                }
                Button(action: onAction) {
                    Text(verbatim: item.actionTitle).font(DSFont.callout.weight(.semibold))
                        .frame(minHeight: HitTarget.minimum - Spacing.sm)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("insight-action")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("insight-card")
    }
}

/// Analysis tab section: current insights plus the history.
struct InsightsSection: View {
    let model: InsightsModel
    var onAction: (InsightItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            if model.current.isEmpty {
                Card {
                    Text(model.isLoading ? "insight.loading" : "insight.empty").font(DSFont.callout).foregroundStyle(DSColor.textSecondary)
                }
                .accessibilityIdentifier("insight-empty")
            } else {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    ForEach(model.current) { item in
                        InsightCardView(item: item, onAction: { onAction(item) }, onDismiss: { Task { await model.dismiss(item) } })
                    }
                }
            }
            if !model.history.isEmpty {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text("insight.history").font(DSFont.headline).foregroundStyle(DSColor.textPrimary).accessibilityAddTraits(.isHeader)
                    ForEach(model.history) { item in
                        Card(padding: Spacing.sm) {
                            HStack(alignment: .top, spacing: Spacing.sm) {
                                Image(systemName: item.icon).foregroundStyle(DSColor.textTertiary).frame(width: 28).accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: Spacing.xxs) {
                                    Text(verbatim: item.title).font(DSFont.callout.weight(.semibold)).foregroundStyle(DSColor.textSecondary)
                                    Text(item.insight.dismissedAt == nil ? "insight.history.resolved" : "insight.history.dismissed")
                                        .font(DSFont.caption).foregroundStyle(DSColor.textTertiary)
                                }
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                .accessibilityIdentifier("insight-history")
            }
        }
    }
}

/// "Add a pulling exercise": the suggested exercises of an insight.
struct InsightSuggestionsSheet: View {
    let sheet: InsightActions.SuggestionSheet
    var onSelect: (String) -> Void

    var body: some View {
        NavigationStack {
            List {
                if sheet.suggestions.isEmpty {
                    Text("insight.suggestions.empty").foregroundStyle(DSColor.textSecondary)
                }
                ForEach(sheet.suggestions) { suggestion in
                    Button { onSelect(suggestion.id) } label: {
                        Text(verbatim: suggestion.name).foregroundStyle(DSColor.textPrimary)
                    }
                    .accessibilityIdentifier("insight-suggestion-\(suggestion.id)")
                }
            }
            .navigationTitle("insight.suggestions.title")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .top) {
                Text(verbatim: sheet.title).font(DSFont.callout).foregroundStyle(DSColor.textSecondary)
                    .padding(.horizontal, Spacing.md).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .presentationDetents([.medium])
    }
}

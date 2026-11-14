import DataKit
import DesignSystem
import SwiftUI

/// Weekly summary (P070): swipeable story cards or a plain list, with access to earlier weeks.
struct WeeklySummaryView: View {
    private enum Layout: String, CaseIterable, Identifiable {
        case stories, list
        var id: String { rawValue }
    }

    @Environment(AppContainer.self) private var container
    @State private var model: WeeklySummaryModel?
    @State private var failed = false
    @State private var layout: Layout = .stories

    var body: some View {
        Group {
            if let model {
                content(model)
            } else if failed {
                ErrorState(message: "weekly.error") { Task { await prepare() } }
            } else {
                LoadingState()
            }
        }
        .background(DSColor.background)
        .navigationTitle("weekly.title")
        .navigationBarTitleDisplayMode(.inline)
        .task { await prepare() }
        .accessibilityIdentifier("weekly-summary-root")
    }

    @ViewBuilder
    private func content(_ model: WeeklySummaryModel) -> some View {
        if model.isLoading {
            LoadingState()
        } else if let week = model.selected {
            VStack(spacing: Spacing.md) {
                header(model, week)
                if layout == .stories { stories(week) } else { list(week) }
            }
            .padding(.top, Spacing.sm)
        }
    }

    private func header(_ model: WeeklySummaryModel, _ week: WeeklySummaryModel.Week) -> some View {
        VStack(spacing: Spacing.sm) {
            Menu {
                ForEach(model.weeks) { option in
                    Button {
                        model.selectedId = option.id
                    } label: {
                        Text(verbatim: option.isCurrent ? "\(option.title) ★" : option.title)
                    }
                }
            } label: {
                Label { Text(verbatim: week.title) } icon: { Image(systemName: "calendar") }
                    .font(DSFont.headline).foregroundStyle(DSColor.textPrimary)
                    .frame(minHeight: HitTarget.minimum)
            }
            .accessibilityIdentifier("weekly-week-picker")
            Picker("weekly.layout", selection: $layout) {
                Text("weekly.layout.stories").tag(Layout.stories)
                Text("weekly.layout.list").tag(Layout.list)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, Spacing.md)
            .accessibilityIdentifier("weekly-layout")
        }
    }

    private func stories(_ week: WeeklySummaryModel.Week) -> some View {
        TabView {
            ForEach(week.cards) { card in
                StoryCardView(card: card).padding(.horizontal, Spacing.md).padding(.bottom, Spacing.xl)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .always))
        .id(week.id)
        .accessibilityIdentifier("weekly-stories")
    }

    private func list(_ week: WeeklySummaryModel.Week) -> some View {
        ScrollView {
            VStack(spacing: Spacing.sm) {
                ForEach(week.cards) { card in
                    Card {
                        HStack(alignment: .top, spacing: Spacing.md) {
                            Image(systemName: card.icon).foregroundStyle(DSColor.accent).frame(width: 28).accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: Spacing.xs) {
                                HStack {
                                    Text(verbatim: card.title).font(DSFont.headline).foregroundStyle(DSColor.textPrimary)
                                    Spacer()
                                    if !card.value.isEmpty {
                                        Text(verbatim: card.value).font(DSFont.headline).foregroundStyle(DSColor.accent)
                                    }
                                }
                                ForEach(card.lines, id: \.self) { line in
                                    Text(verbatim: line).font(DSFont.callout).foregroundStyle(DSColor.textSecondary)
                                }
                            }
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(Spacing.md)
        }
        .accessibilityIdentifier("weekly-list")
    }

    private func prepare() async {
        guard model == nil else { return }
        guard let created = await container.makeWeeklySummaryModel() else {
            failed = true
            return
        }
        failed = false
        model = created
        await created.load()
    }
}

private struct StoryCardView: View {
    let card: WeeklyCard

    var body: some View {
        Card {
            VStack(spacing: Spacing.md) {
                Image(systemName: card.icon).font(.system(size: 36)).foregroundStyle(DSColor.accent).accessibilityHidden(true)
                Text(verbatim: card.title).font(DSFont.overline).foregroundStyle(DSColor.textSecondary)
                if !card.value.isEmpty {
                    Text(verbatim: card.value).font(DSFont.display).foregroundStyle(DSColor.textPrimary)
                        .minimumScaleFactor(0.5).lineLimit(1)
                }
                ForEach(card.lines, id: \.self) { line in
                    Text(verbatim: line).font(DSFont.body).foregroundStyle(DSColor.textSecondary).multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(Spacing.md)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("weekly-card-\(card.kind.rawValue)")
    }
}

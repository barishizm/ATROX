import DataKit
import DesignSystem
import SwiftUI

/// Exercise library: sections (recent / favorites / all), instant search, filters, favorites and, when `onAdd` is
/// given, a multi-select mode with an "Add (n)" button.
struct LibraryView: View {
    @Environment(AppContainer.self) private var container
    @Environment(\.locale) private var locale
    @Environment(\.dismiss) private var dismiss
    @State private var model: LibraryModel?
    @State private var failed = false
    @State private var showFilters = false
    /// Non-nil switches the screen into selection mode.
    var onAdd: (([String]) -> Void)?

    var body: some View {
        Group {
            if let model {
                content(model)
            } else if failed {
                ErrorState(message: "library.error.load") { Task { await prepare() } }
            } else {
                LoadingState()
            }
        }
        .background(DSColor.background)
        .navigationTitle("library.exercises.title")
        .navigationBarTitleDisplayMode(.inline)
        .task { await prepare() }
        .accessibilityIdentifier("library-root")
    }

    @ViewBuilder
    private func content(_ model: LibraryModel) -> some View {
        @Bindable var model = model
        Group {
            switch model.loadState {
            case .loading: LoadingState()
            case .failed: ErrorState(message: "library.error.load") { Task { await model.load() } }
            case .loaded: list(model)
            }
        }
        .searchable(text: $model.query, placement: .navigationBarDrawer(displayMode: .always), prompt: "library.search.prompt")
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .toolbar { toolbar(model) }
        .sheet(isPresented: $showFilters) { LibraryFilterSheet(model: model) }
        .onAppear { model.languageCode = locale.language.languageCode?.identifier == "tr" ? "tr" : "en" }
        .onChange(of: locale) { _, new in model.languageCode = new.language.languageCode?.identifier == "tr" ? "tr" : "en" }
    }

    private func list(_ model: LibraryModel) -> some View {
        List {
            if model.isEquipmentSuggestion {
                Section {
                    HStack {
                        Label("library.filter.suggestion", systemImage: "dumbbell").font(DSFont.callout)
                        Spacer()
                        Button("library.filter.showAll") { model.clearFilters() }.font(DSFont.callout.weight(.semibold))
                    }
                    .accessibilityIdentifier("library-suggestion")
                }
            }
            if model.resultCount == 0 {
                EmptyState(systemImage: "magnifyingglass", title: "library.empty.title", message: "library.empty.message")
                    .listRowBackground(Color.clear)
            }
            ForEach(model.sections) { section in
                Section {
                    ForEach(section.items) { item in row(item, model: model) }
                } header: {
                    Text(title(of: section.kind))
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
    }

    private func row(_ item: ExerciseListItem, model: LibraryModel) -> some View {
        let selecting = onAdd != nil
        let selected = model.isSelected(item.id)
        let favorite = model.lists.isFavorite(item.id)
        return HStack(spacing: Spacing.md) {
            if selecting {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? DSColor.accent : DSColor.textTertiary)
                    .font(.title3)
                    .accessibilityHidden(true)
            }
            ExerciseThumbnail(fileName: item.thumbnailName)
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(verbatim: item.name(languageCode: model.languageCode))
                    .font(DSFont.body.weight(.semibold)).foregroundStyle(DSColor.textPrimary).lineLimit(2)
                HStack(spacing: Spacing.xs) {
                    if let muscle = item.primaryMuscle.flatMap(Muscle.init(rawValue:)) {
                        Text(verbatim: muscle.localizedName(locale: locale))
                    }
                    Text(equipmentKey(item.equipment)).foregroundStyle(DSColor.textTertiary)
                }
                .font(DSFont.caption).foregroundStyle(DSColor.textSecondary)
            }
            Spacer(minLength: Spacing.sm)
            Button {
                model.toggleFavorite(item.id)
            } label: {
                Image(systemName: favorite ? "star.fill" : "star")
                    .foregroundStyle(favorite ? DSColor.warning : DSColor.textTertiary)
                    .frame(minWidth: HitTarget.minimum, minHeight: HitTarget.minimum)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(favorite ? "library.favorite.remove" : "library.favorite.add")
        }
        .contentShape(Rectangle())
        .onTapGesture { if selecting { model.toggleSelection(item.id) } }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("library-row-\(item.id)")
    }

    @ToolbarContentBuilder
    private func toolbar(_ model: LibraryModel) -> some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button { showFilters = true } label: {
                Image(systemName: model.filter.isActive
                    ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
            }
            .accessibilityLabel("library.filter.button")
            .accessibilityValue(model.filter.isActive ? Text(verbatim: "\(model.filter.activeCount)") : Text(verbatim: ""))
            .accessibilityIdentifier("library-filter-button")
        }
        if let onAdd {
            ToolbarItem(placement: .topBarLeading) {
                Button("library.select.cancel") { dismiss() }
            }
            ToolbarItem(placement: .bottomBar) {
                Button {
                    onAdd(model.confirmSelection())
                } label: {
                    Text("library.select.add \(model.selectionCount)").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.selectionCount == 0)
                .accessibilityIdentifier("library-add-button")
            }
        }
    }

    private func title(of kind: LibraryModel.SectionKind) -> LocalizedStringKey {
        switch kind {
        case .recent: "library.section.recent"
        case .favorites: "library.section.favorites"
        case .all: "library.section.all"
        case .results: "library.section.results"
        }
    }

    private func prepare() async {
        guard model == nil else { return }
        guard let created = await container.makeLibraryModel() else {
            failed = true
            return
        }
        failed = false
        model = created
        await created.load()
    }
}

/// `LocalizedStringKey` for a catalog equipment value (nil = no equipment).
func equipmentKey(_ raw: String?) -> LocalizedStringKey {
    LocalizedStringKey("library.equipment.\(raw ?? ExerciseFilter.noEquipmentToken)")
}

struct LibraryFilterSheet: View {
    let model: LibraryModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            Form {
                Section("library.filter.muscles") {
                    FlowChips(
                        options: Muscle.allCases.map { ($0.rawValue, Text(verbatim: $0.localizedName(locale: locale))) },
                        selection: $model.filter.muscles
                    )
                }
                Section("library.filter.equipment") {
                    FlowChips(
                        options: model.availableEquipment.map { raw in
                            (raw, Text(equipmentKey(raw == ExerciseFilter.noEquipmentToken ? nil : raw)))
                        },
                        selection: $model.filter.equipment
                    )
                    if model.hasEquipmentSuggestion {
                        Button("library.filter.useMyEquipment") { model.useSuggestedEquipment() }
                    }
                }
                Section {
                    Toggle(isOn: $model.filter.scorableOnly) {
                        VStack(alignment: .leading) {
                            Text("library.filter.scorableOnly")
                            Text("library.filter.scorableOnly.detail").font(DSFont.caption).foregroundStyle(DSColor.textSecondary)
                        }
                    }
                }
            }
            .navigationTitle("library.filter.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("library.filter.clear") { model.clearFilters() }.disabled(!model.filter.isActive)
                }
                ToolbarItem(placement: .topBarTrailing) { Button("library.filter.done") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

/// Wrapping multi-select chips.
private struct FlowChips: View {
    let options: [(id: String, label: Text)]
    @Binding var selection: Set<String>

    var body: some View {
        FlowLayout(spacing: Spacing.sm) {
            ForEach(options, id: \.id) { option in
                let on = selection.contains(option.id)
                Button {
                    if on { selection.remove(option.id) } else { selection.insert(option.id) }
                } label: {
                    option.label
                        .font(DSFont.callout)
                        .padding(.horizontal, Spacing.md).padding(.vertical, Spacing.sm)
                        .foregroundStyle(on ? DSColor.onAccent : DSColor.textPrimary)
                        .background(on ? DSColor.accent : DSColor.surfaceRaised, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(.vertical, Spacing.xs)
    }
}

private struct FlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(proposal.width ?? 320, subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(bounds.width, subviews)
        for (index, origin) in result.origins.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y), proposal: .unspecified)
        }
    }

    private func arrange(_ width: CGFloat, _ subviews: Subviews) -> (size: CGSize, origins: [CGPoint]) {
        var origins: [CGPoint] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            origins.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            maxX = max(maxX, x - spacing)
        }
        return (CGSize(width: maxX, height: y + rowHeight), origins)
    }
}

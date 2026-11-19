import DataKit
import DesignSystem
import PhotosUI
import SwiftUI

/// The nutrition screen: the day's calories and macros against the target, the meals, and the ways to add food.
struct NutritionRootView: View {
    @Environment(AppContainer.self) private var container
    @Environment(\.locale) private var locale
    @State private var model: NutritionModel?
    @State private var consent: FoodConsentModel?
    @State private var sheet: NutritionSheet?
    @State private var showsAddMenu = false
    @State private var showsCamera = false
    @State private var showsLibrary = false
    @State private var photoItem: PhotosPickerItem?
    @State private var pending: AIAction?
    @State private var unavailable = false

    private enum AIAction { case camera, library, describe }

    var body: some View {
        Group {
            if let model {
                content(model)
            } else if unavailable {
                EmptyState(systemImage: "fork.knife", title: "nutrition.unavailable.title", message: "nutrition.unavailable.message")
            } else {
                LoadingState()
            }
        }
        .background(DSColor.background.ignoresSafeArea())
        .navigationTitle("nutrition.title")
        .toolbar { if model != nil { ToolbarItem(placement: .primaryAction) { optionsMenu } } }
        .task { await prepare() }
        .task(id: container.dataRevision) { await model?.load() }
        .sheet(item: $sheet) { sheet in sheetContent(sheet) }
        .fullScreenCover(isPresented: $showsCamera) {
            CameraPicker { image in
                showsCamera = false
                if let image { startPhoto(image) }
            }
            .ignoresSafeArea()
        }
        .photosPicker(isPresented: $showsLibrary, selection: $photoItem, matching: .images)
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            photoItem = nil
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) { startPhoto(image) }
            }
        }
        .onChange(of: consent?.state) { _, state in
            guard state == .granted, let action = pending else { return }
            pending = nil
            sheet = nil
            // Wait for the consent sheet to leave before presenting the next surface.
            Task {
                try? await Task.sleep(for: .milliseconds(400))
                run(action)
            }
        }
        .accessibilityIdentifier("nutrition-root")
    }

    // MARK: Content

    private func content(_ model: NutritionModel) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                dayHeader(model)
                if model.isLoading {
                    LoadingState()
                } else {
                    summaryCard(model)
                    if let left = model.analysesLeft { quotaChip(left) }
                    mealsSection(model)
                }
            }
            .padding(Spacing.md)
            .padding(.bottom, 80)
        }
        .safeAreaInset(edge: .bottom) { addBar }
        .refreshable { await model.load() }
    }

    private func dayHeader(_ model: NutritionModel) -> some View {
        HStack {
            Button { Task { await model.shiftDay(by: -1) } } label: { Image(systemName: "chevron.left") }
                .frame(minWidth: HitTarget.minimum, minHeight: HitTarget.minimum)
                .accessibilityLabel(Text("nutrition.day.previous"))
            Spacer()
            VStack(spacing: Spacing.xxs) {
                Text(model.isToday ? "nutrition.day.today" : LocalizedStringKey(""))
                    .font(DSFont.overline).foregroundStyle(DSColor.accent).opacity(model.isToday ? 1 : 0)
                Text(model.day.formatted(.dateTime.weekday(.wide).day().month(.wide))).font(DSFont.headline).foregroundStyle(DSColor.textPrimary)
            }
            .accessibilityElement(children: .combine)
            Spacer()
            Button { Task { await model.shiftDay(by: 1) } } label: { Image(systemName: "chevron.right") }
                .frame(minWidth: HitTarget.minimum, minHeight: HitTarget.minimum)
                .disabled(!model.canGoForward)
                .accessibilityLabel(Text("nutrition.day.next"))
        }
    }

    private func summaryCard(_ model: NutritionModel) -> some View {
        Card {
            VStack(spacing: Spacing.md) {
                CalorieRing(consumed: model.summary.calories, target: model.target?.values.calories)
                    .frame(maxWidth: .infinity)
                HStack(alignment: .top, spacing: Spacing.md) {
                    MacroBar(title: "nutrition.macro.protein", grams: model.summary.proteinG, target: model.target?.values.proteinG, tint: DSColor.accent)
                    MacroBar(title: "nutrition.macro.carbs", grams: model.summary.carbsG, target: model.target?.values.carbsG, tint: DSColor.highlight)
                    MacroBar(title: "nutrition.macro.fat", grams: model.summary.fatG, target: model.target?.values.fatG, tint: DSColor.success)
                }
                if let target = model.target {
                    Button { sheet = .target } label: {
                        Label(
                            target.mode == .auto ? "nutrition.target.fromprofile" : "nutrition.target.fromyou",
                            systemImage: target.mode == .auto ? "wand.and.stars" : "slider.horizontal.3"
                        )
                        .font(DSFont.footnote)
                    }
                    .accessibilityIdentifier("nutrition-target-edit")
                } else {
                    VStack(spacing: Spacing.xs) {
                        Text("nutrition.target.missing").font(DSFont.callout).foregroundStyle(DSColor.textSecondary).multilineTextAlignment(.center)
                        SecondaryButton("nutrition.target.set", systemImage: "target") { sheet = .target }
                            .accessibilityIdentifier("nutrition-target-set")
                    }
                }
            }
        }
        .accessibilityIdentifier("nutrition-summary")
    }

    private func quotaChip(_ left: Int) -> some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: "sparkles").accessibilityHidden(true)
            Text(verbatim: "\(left)")
            Text("nutrition.quota.left")
        }
        .font(DSFont.footnote).foregroundStyle(DSColor.textSecondary)
    }

    @ViewBuilder
    private func mealsSection(_ model: NutritionModel) -> some View {
        if model.summary.entries.isEmpty {
            EmptyState(systemImage: "fork.knife", title: "nutrition.empty.title", message: "nutrition.empty.message")
                .frame(minHeight: 220)
        } else {
            ForEach(MealType.allCases, id: \.self) { meal in
                let entries = model.entries(for: meal)
                if !entries.isEmpty {
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        HStack {
                            Label { Text(meal.titleKey) } icon: { Image(systemName: meal.systemImage) }
                                .font(DSFont.headline).foregroundStyle(DSColor.textPrimary)
                            Spacer()
                            Text(verbatim: "\(Int(entries.reduce(0) { $0 + $1.input.calories }.rounded())) kcal")
                                .font(DSFont.numericSmall).foregroundStyle(DSColor.textSecondary)
                        }
                        ForEach(entries) { entry in entryRow(entry, model) }
                    }
                }
            }
        }
    }

    private func entryRow(_ entry: FoodEntrySnapshot, _ model: NutritionModel) -> some View {
        let input = entry.input
        return Button { sheet = .manual(entry) } label: {
            Card(padding: Spacing.sm) {
                HStack(spacing: Spacing.sm) {
                    thumbnail(input)
                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        Text(input.name).font(DSFont.callout.weight(.semibold)).foregroundStyle(DSColor.textPrimary).lineLimit(2)
                        Text(verbatim: "P \(Int(input.proteinG.rounded())) · C \(Int(input.carbsG.rounded())) · F \(Int(input.fatG.rounded()))")
                            .font(DSFont.caption).foregroundStyle(DSColor.textSecondary)
                    }
                    Spacer()
                    Text(verbatim: "\(Int(input.calories.rounded()))").font(DSFont.numericSmall).foregroundStyle(DSColor.textPrimary)
                    Text(verbatim: "kcal").font(DSFont.caption).foregroundStyle(DSColor.textSecondary)
                }
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button { sheet = .manual(entry) } label: { Label("nutrition.entry.edit", systemImage: "pencil") }
            Button(role: .destructive) { Task { await model.delete(id: entry.id) } } label: { Label("nutrition.entry.delete", systemImage: "trash") }
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text("nutrition.entry.hint"))
    }

    @ViewBuilder
    private func thumbnail(_ input: FoodEntryInput) -> some View {
        if let data = input.thumbnail, let image = UIImage(data: data) {
            Image(uiImage: image).resizable().scaledToFill().frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)).accessibilityHidden(true)
        } else {
            Image(systemName: input.source.systemImage).frame(width: 44, height: 44).foregroundStyle(DSColor.accent)
                .background(DSColor.surfaceRaised, in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)).accessibilityHidden(true)
        }
    }

    // MARK: Add

    private var addBar: some View {
        HStack(spacing: Spacing.sm) {
            PrimaryButton("nutrition.add.scan", systemImage: "camera.fill") { request(CameraPicker.isAvailable ? .camera : .library) }
                .accessibilityIdentifier("nutrition-scan")
            Button { showsAddMenu = true } label: {
                Image(systemName: "plus").font(.title3.weight(.semibold)).frame(width: HitTarget.button, height: HitTarget.button)
                    .background(DSColor.surfaceRaised, in: Circle())
            }
            .accessibilityLabel(Text("nutrition.add.more"))
            .accessibilityIdentifier("nutrition-add-more")
        }
        .padding(.horizontal, Spacing.md).padding(.vertical, Spacing.sm)
        .background(.ultraThinMaterial)
        .confirmationDialog("nutrition.add.more", isPresented: $showsAddMenu) {
            if CameraPicker.isAvailable { Button("nutrition.add.camera") { request(.camera) } }
            Button("nutrition.add.library") { request(.library) }
            Button("nutrition.add.describe") { request(.describe) }
            Button("nutrition.add.barcode") { sheet = .barcode }
            Button("nutrition.add.manual") { sheet = .manual(nil) }
            Button("common.cancel", role: .cancel) {}
        }
    }

    private var optionsMenu: some View {
        Menu {
            Button { sheet = .target } label: { Label("nutrition.target.set", systemImage: "target") }
            if consent?.isGranted == true {
                Button(role: .destructive) { Task { await consent?.decline() } } label: { Label("nutrition.consent.withdraw", systemImage: "hand.raised") }
            }
        } label: { Image(systemName: "ellipsis.circle") }
        .accessibilityLabel(Text("nutrition.options"))
    }

    /// AI features need the food-photo consent first; the others do not.
    private func request(_ action: AIAction) {
        guard let consent else { return }
        if consent.isGranted {
            run(action)
        } else {
            pending = action
            sheet = .consent
        }
    }

    private func run(_ action: AIAction) {
        switch action {
        case .camera: showsCamera = true
        case .library: showsLibrary = true
        case .describe: sheet = .analyze(makeModel(.text))
        }
    }

    private func startPhoto(_ image: UIImage) {
        guard let jpeg = FoodImage.jpeg(from: image) else { return }
        sheet = .analyze(makeModel(.photo(jpeg: jpeg, thumbnail: FoodImage.thumbnail(from: image))))
    }

    private func makeModel(_ source: FoodAnalyzeModel.Source) -> AnalyzeLaunch {
        AnalyzeLaunch(model: FoodAnalyzeModel(source: source, service: container.coach?.food, locale: locale.language.languageCode?.identifier ?? "en"))
    }

    // MARK: Sheets

    @ViewBuilder
    private func sheetContent(_ sheet: NutritionSheet) -> some View {
        switch sheet {
        case .analyze(let launch):
            FoodAnalyzeView(model: launch.model, onSave: { await model?.save($0) ?? false }, onClose: { self.sheet = nil })
                .onChange(of: launch.model.remaining) { _, left in if let left { model?.analysesLeft = left } }
        case .manual(let entry):
            ManualFoodView(
                editing: entry,
                onSave: { input in
                    if let entry { return await model?.update(id: entry.id, with: input) ?? false }
                    return await model?.save(input) ?? false
                },
                onClose: { self.sheet = nil }
            )
        case .barcode:
            BarcodeLookupView(
                service: container.packagedFoods, languageCode: locale.language.languageCode?.identifier ?? "en",
                onSelect: { food in self.sheet = .analyze(AnalyzeLaunch(model: FoodAnalyzeModel(food: food))) },
                onClose: { self.sheet = nil }
            )
        case .target:
            NutritionTargetSetupView(
                profile: model?.profile, current: model?.target, onSave: { await model?.setTarget($0) ?? false }, onClose: { self.sheet = nil }
            )
        case .consent:
            if let consent {
                FoodConsentView(model: consent) { if !consent.isGranted { pending = nil; self.sheet = nil } }
            }
        }
    }

    private func prepare() async {
        guard model == nil else { return }
        guard let made = await container.makeNutritionModel(), let agreed = await container.foodConsent() else {
            unavailable = true
            return
        }
        consent = agreed
        model = made
        await made.load()
    }
}

struct AnalyzeLaunch: Identifiable {
    let id = UUID()
    let model: FoodAnalyzeModel
}

enum NutritionSheet: Identifiable {
    case analyze(AnalyzeLaunch)
    case manual(FoodEntrySnapshot?)
    case barcode
    case target
    case consent

    var id: String {
        switch self {
        case .analyze(let launch): "analyze-\(launch.id)"
        case .manual(let entry): "manual-\(entry?.id.uuidString ?? "new")"
        case .barcode: "barcode"
        case .target: "target"
        case .consent: "consent"
        }
    }
}

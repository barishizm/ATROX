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
    @State private var tab: NutritionTab = .diary
    @State private var showsAddMenu = false
    @State private var showsCalendar = false
    @State private var detailMeal: MealType?
    /// The meal the next added food goes to; nil picks one from the time of day.
    @State private var addMeal: MealType?
    @State private var showsCamera = false
    @State private var showsLibrary = false
    @State private var photoItem: PhotosPickerItem?
    /// The photo just taken: analysis starts once the camera has fully left, never in the same update that dismisses it.
    @State private var capturedImage: UIImage?
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
        .toolbar(.hidden, for: .navigationBar)
        .task { await prepare() }
        .task(id: container.dataRevision) { await model?.load() }
        .sheet(item: $sheet) { sheet in sheetContent(sheet) }
        .sheet(isPresented: $showsCalendar) {
            NutritionCalendarSheet(selection: model?.day ?? Date()) { picked in Task { await model?.select(day: picked) } }
        }
        .navigationDestination(item: $detailMeal) { meal in
            if let model {
                MealDetailView(model: model, meal: meal, onAdd: { addMeal = meal; showsAddMenu = true }, onEdit: { sheet = .manual($0) })
            }
        }
        .confirmationDialog("nutrition.add.more", isPresented: $showsAddMenu) {
            if CameraPicker.isAvailable { Button("nutrition.add.camera") { request(.camera) } }
            Button("nutrition.add.library") { request(.library) }
            Button("nutrition.add.describe") { request(.describe) }
            Button("nutrition.add.barcode") { sheet = .barcode }
            Button("nutrition.add.manual") { sheet = .manual(nil) }
            Button("common.cancel", role: .cancel) {}
        }
        .fullScreenCover(isPresented: $showsCamera, onDismiss: {
            guard let image = capturedImage else { return }
            capturedImage = nil
            startPhoto(image)
        }) {
            CameraPicker { image in
                capturedImage = image
                showsCamera = false
            }
            .ignoresSafeArea()
        }
        .photosPicker(isPresented: $showsLibrary, selection: $photoItem, matching: .images)
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            photoItem = nil
            Task {
                guard let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else { return }
                // The photo picker is still leaving; a sheet presented in the same moment would be dropped.
                try? await Task.sleep(for: .milliseconds(450))
                startPhoto(image)
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
                NutritionHeader(title: dayTitle(model), streak: model.streak, onCalendar: { showsCalendar = true }) { optionsMenu }
                NutritionTabPicker(selection: $tab)
                switch tab {
                case .diary: diary(model)
                case .recipes:
                    EmptyState(systemImage: "book.closed", title: "nutrition.recipes.empty.title", message: "nutrition.recipes.empty.message")
                        .frame(minHeight: 320).accessibilityIdentifier("nutrition-recipes")
                }
            }
            .padding(Spacing.md)
            .padding(.bottom, Spacing.xl)
        }
        .refreshable { await model.load() }
    }

    @ViewBuilder
    private func diary(_ model: NutritionModel) -> some View {
        if model.isLoading {
            LoadingState()
        } else {
            if model.trackedDays.count < 3 { NutritionTrackProgress(trackedDays: model.trackedDays.count) }
            Text("nutrition.summary.title").font(DSFont.title).foregroundStyle(DSColor.textPrimary)
            NutritionSummaryCard(model: model) { sheet = .target }
            if let left = model.analysesLeft { quotaChip(left) }
            Text("nutrition.title").font(DSFont.title).foregroundStyle(DSColor.textPrimary)
            NutritionMealsCard(model: model, onOpen: { detailMeal = $0 }, onAdd: { addMeal = $0; showsAddMenu = true })
        }
    }

    private func dayTitle(_ model: NutritionModel) -> Text {
        model.isToday ? Text("nutrition.day.today.title") : Text(model.day.formatted(.dateTime.day().month(.abbreviated)))
    }

    private func quotaChip(_ left: Int) -> some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: "sparkles").accessibilityHidden(true)
            Text(verbatim: "\(left)")
            Text("nutrition.quota.left")
        }
        .font(DSFont.footnote).foregroundStyle(DSColor.textSecondary)
    }

    private var optionsMenu: some View {
        Menu {
            Button { sheet = .target } label: { Label("nutrition.target.set", systemImage: "target") }
            if consent?.isGranted == true {
                Button(role: .destructive) { Task { await consent?.decline() } } label: { Label("nutrition.consent.withdraw", systemImage: "hand.raised") }
            }
        } label: { Image(systemName: "ellipsis").font(.title3.weight(.semibold)) }
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
        let analysis = FoodAnalyzeModel(source: source, service: container.coach?.food, locale: locale.language.languageCode?.identifier ?? "en")
        if let addMeal { analysis.meal = addMeal }
        return AnalyzeLaunch(model: analysis)
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
                editing: entry, meal: addMeal,
                onSave: { input in
                    if let entry { return await model?.update(id: entry.id, with: input) ?? false }
                    return await model?.save(input) ?? false
                },
                onClose: { self.sheet = nil }
            )
        case .barcode:
            BarcodeLookupView(
                service: container.packagedFoods, languageCode: locale.language.languageCode?.identifier ?? "en",
                onSelect: { food in
                    let analysis = FoodAnalyzeModel(food: food)
                    if let addMeal { analysis.meal = addMeal }
                    self.sheet = .analyze(AnalyzeLaunch(model: analysis))
                },
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

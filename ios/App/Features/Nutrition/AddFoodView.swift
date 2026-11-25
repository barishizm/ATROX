import DataKit
import DesignSystem
import PhotosUI
import SwiftUI

/// The "+" of a meal: search (the default) with the most logged foods one tap away, plus camera, barcode, voice/text and more.
struct AddFoodView: View {
    let model: NutritionModel
    let consent: FoodConsentModel
    let meal: MealType
    let onClose: () -> Void

    @Environment(AppContainer.self) private var container
    @Environment(\.locale) private var locale

    @State private var query = ""
    @State private var packaged: [PackagedFood] = []
    /// Foods that show the check mark right now (it fades back to "+" after a moment).
    @State private var added: Set<String> = []
    @State private var saveFailed = false
    @State private var sheet: Sheet?
    @State private var cover: Cover?
    @State private var showsText = false
    @State private var showsLibrary = false
    @State private var description = ""
    @State private var photoItem: PhotosPickerItem?
    @State private var pending: AIAction?
    /// Set while a full-screen cover leaves; the next surface starts only once it has fully gone.
    @State private var capturedImage: UIImage?
    @State private var scannedFood: PackagedFood?
    @State private var savedFromAnalysis = false

    private enum AIAction { case camera, library, text }
    private enum Cover: String, Identifiable { case camera, scanner; var id: String { rawValue } }
    private enum Sheet: Identifiable {
        case promo, consent, manual, analyze(AnalyzeLaunch)
        var id: String {
            switch self {
            case .promo: "promo"
            case .consent: "consent"
            case .manual: "manual"
            case .analyze(let launch): "analyze-\(launch.id)"
            }
        }
    }

    private var isPro: Bool { !FeatureGate.isLocked(.foodAnalysisUnlimited, isPro: container.purchases.isPro) }
    private var languageCode: String { locale.language.languageCode?.identifier ?? "en" }

    private var foods: [CommonFood] {
        CommonFood.filter(CommonFood.all, query: query, name: { $0.name(in: locale) })
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.md) {
                        modeTiles
                        searchField
                        list
                    }
                    .padding(.horizontal, Spacing.md).padding(.bottom, Spacing.md)
                }
                .scrollDismissesKeyboard(.interactively)
                PrimaryButton("nutrition.addfood.done") { onClose() }
                    .padding(Spacing.md).accessibilityIdentifier("add-food-done")
            }
            .background(DSColor.background.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(isPresented: $showsText) {
                TextMealView(text: $description, onAnalyze: startText)
            }
        }
        .task(id: query) { await searchPackaged() }
        .sheet(item: $sheet) { sheetContent($0) }
        .fullScreenCover(item: $cover, onDismiss: coverDismissed) { coverContent($0) }
        .photosPicker(isPresented: $showsLibrary, selection: $photoItem, matching: .images)
        .onChange(of: photoItem) { _, item in loadPhoto(item) }
        .onChange(of: consent.state) { _, state in consentChanged(state) }
        .onChange(of: isPro) { _, pro in if pro, case .promo = sheet { sheet = nil } }
        .accessibilityIdentifier("add-food")
    }

    // MARK: Header and tiles

    private var header: some View {
        ZStack {
            Text(meal.titleKey).font(DSFont.headline).foregroundStyle(DSColor.textPrimary)
            HStack {
                mealRing
                Spacer()
            }
        }
        .padding(Spacing.md)
    }

    private var mealRing: some View {
        let eaten = Int(model.calories(for: meal).rounded())
        return Text(verbatim: "\(eaten)").font(DSFont.numericSmall).foregroundStyle(DSColor.textPrimary).minimumScaleFactor(0.5).lineLimit(1)
            .frame(width: 36, height: 36)
            .overlay(Circle().strokeBorder(DSColor.accent, lineWidth: 2.5))
            .padding(4).glassEffect(Glass.regular, in: Circle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("nutrition.addfood.calories.a11y \(eaten)"))
            .accessibilityIdentifier("add-food-ring")
    }

    private var modeTiles: some View {
        HStack(alignment: .top, spacing: Spacing.xs) {
            tile("magnifyingglass", "nutrition.addfood.search", selected: true) { }
                .accessibilityIdentifier("add-food-search")
            tile("camera.fill", "nutrition.addfood.camera") { request(.camera) }.accessibilityIdentifier("add-food-camera")
            tile("barcode.viewfinder", "nutrition.addfood.barcode") { cover = .scanner }.accessibilityIdentifier("add-food-barcode")
            tile("text.bubble.fill", "nutrition.addfood.voice", badge: "nutrition.addfood.new") { request(.text) }
                .accessibilityIdentifier("add-food-text")
            Menu {
                Button { request(.library) } label: { Label("nutrition.add.library", systemImage: "photo") }
                Button { sheet = .manual } label: { Label("nutrition.add.manual", systemImage: "square.and.pencil") }
            } label: {
                tileLabel("ellipsis", "nutrition.addfood.more", selected: false, badge: nil)
            }
            .accessibilityIdentifier("add-food-more")
        }
    }

    private func tile(
        _ icon: String, _ title: LocalizedStringKey, selected: Bool = false, badge: LocalizedStringKey? = nil, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) { tileLabel(icon, title, selected: selected, badge: badge) }
            .buttonStyle(.plain)
            .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func tileLabel(_ icon: String, _ title: LocalizedStringKey, selected: Bool, badge: LocalizedStringKey?) -> some View {
        VStack(spacing: Spacing.xs) {
            Image(systemName: icon).font(.title2).foregroundStyle(selected ? DSColor.accent : DSColor.textPrimary)
                .frame(maxWidth: .infinity, minHeight: 60)
                .background(selected ? DSColor.accentFill.opacity(0.25) : DSColor.surface, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(selected ? DSColor.accent : DSColor.separator, lineWidth: selected ? 2 : 1)
                )
                .overlay(alignment: .top) {
                    if let badge {
                        Text(badge).font(DSFont.overline).foregroundStyle(DSColor.onHighlight).padding(.horizontal, 6).padding(.vertical, 2)
                            .background(DSColor.highlightFill, in: Capsule()).offset(y: -9)
                    }
                }
            Text(title).font(DSFont.caption).foregroundStyle(selected ? DSColor.textPrimary : DSColor.textSecondary).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 6)
        .contentShape(Rectangle())
    }

    private var searchField: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "magnifyingglass").foregroundStyle(DSColor.textSecondary).accessibilityHidden(true)
            TextField("nutrition.addfood.placeholder", text: $query).submitLabel(.search).autocorrectionDisabled()
                .foregroundStyle(DSColor.textPrimary).accessibilityIdentifier("add-food-query")
            if !query.isEmpty {
                Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(DSColor.textTertiary) }
                    .accessibilityLabel(Text("common.cancel"))
            }
        }
        .padding(.horizontal, Spacing.md).frame(minHeight: HitTarget.button)
        .background(DSColor.surface, in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(DSColor.accent, lineWidth: 2))
    }

    // MARK: List

    private var list: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !foods.isEmpty {
                Text("nutrition.addfood.frequent").font(DSFont.overline).foregroundStyle(DSColor.textSecondary).padding(.bottom, Spacing.xs)
                ForEach(foods) { food in
                    commonRow(food)
                    Divider().overlay(DSColor.separator)
                }
            }
            if !packaged.isEmpty {
                Text("nutrition.addfood.packaged").font(DSFont.overline).foregroundStyle(DSColor.textSecondary).padding(.vertical, Spacing.xs)
                ForEach(packaged) { food in
                    packagedRow(food)
                    Divider().overlay(DSColor.separator)
                }
            }
            if saveFailed { Text("nutrition.save.failed").font(DSFont.footnote).foregroundStyle(DSColor.error).padding(.top, Spacing.sm) }
        }
    }

    private func commonRow(_ food: CommonFood) -> some View {
        let done = added.contains(food.id)
        return HStack(spacing: Spacing.sm) {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(LocalizedStringKey(food.nameKey)).font(DSFont.body).foregroundStyle(DSColor.textPrimary)
                Text(LocalizedStringKey(food.servingKey)).font(DSFont.footnote).foregroundStyle(DSColor.textSecondary)
            }
            Spacer(minLength: Spacing.sm)
            Text("nutrition.addfood.kcal \(Int(food.calories.rounded()))").font(DSFont.numericSmall).foregroundStyle(DSColor.textSecondary)
            addButton(done: done) { quickAdd(food) }
                .accessibilityIdentifier("add-food-\(food.id)")
        }
        .padding(.vertical, Spacing.sm)
        .accessibilityElement(children: .contain)
    }

    private func packagedRow(_ food: PackagedFood) -> some View {
        HStack(spacing: Spacing.sm) {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(food.displayName).font(DSFont.body).foregroundStyle(DSColor.textPrimary).lineLimit(2)
                Text(verbatim: "\(Int(food.defaultGrams.rounded())) g").font(DSFont.footnote).foregroundStyle(DSColor.textSecondary)
            }
            Spacer(minLength: Spacing.sm)
            Text("nutrition.addfood.kcal \(Int((food.caloriesPer100g * food.defaultGrams / 100).rounded()))")
                .font(DSFont.numericSmall).foregroundStyle(DSColor.textSecondary)
            addButton(done: false) { openEditor(for: food, source: .search) }
        }
        .padding(.vertical, Spacing.sm)
    }

    private func addButton(done: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                Image(systemName: "plus.circle").foregroundStyle(DSColor.accent)
                    .opacity(done ? 0 : 1).scaleEffect(done ? 0.4 : 1)
                Image(systemName: "checkmark.circle.fill").foregroundStyle(DSColor.success)
                    .opacity(done ? 1 : 0).scaleEffect(done ? 1 : 0.4)
            }
            .font(.system(size: 30, weight: .regular))
            .animation(.spring(duration: 0.35, bounce: 0.4), value: done)
            .frame(width: HitTarget.minimum, height: HitTarget.minimum)
        }
        .buttonStyle(.plain).allowsHitTesting(!done)
        .accessibilityLabel(Text(done ? "nutrition.addfood.added" : "nutrition.addfood.add"))
    }

    private func quickAdd(_ food: CommonFood) {
        guard !added.contains(food.id) else { return }
        saveFailed = false
        // The check shows at once; it is taken back if the save fails.
        added.insert(food.id)
        Task {
            let input = food.entryInput(name: food.name(in: locale), meal: meal, eatenAt: model.moment())
            guard await model.save(input) else {
                added.remove(food.id)
                saveFailed = true
                Haptics.play(.error)
                return
            }
            Haptics.play(.success)
            try? await Task.sleep(for: .seconds(2.5))
            added.remove(food.id)
        }
    }

    private func searchPackaged() async {
        let terms = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard terms.count >= 2 else {
            packaged = []
            return
        }
        // Typing pauses: only the last query reaches Open Food Facts.
        try? await Task.sleep(for: .milliseconds(450))
        guard !Task.isCancelled else { return }
        let results = (try? await container.packagedFoods.search(terms, languageCode: languageCode)) ?? []
        guard !Task.isCancelled else { return }
        packaged = results
    }

    // MARK: Flows

    /// Photo analysis is Pro; every AI action needs the food-photo consent first.
    private func request(_ action: AIAction) {
        if action != .text, !isPro {
            sheet = .promo
            return
        }
        guard consent.isGranted else {
            pending = action
            sheet = .consent
            return
        }
        run(action)
    }

    private func run(_ action: AIAction) {
        switch action {
        case .camera: if CameraPicker.isAvailable { cover = .camera } else { showsLibrary = true }
        case .library: showsLibrary = true
        case .text: showsText = true
        }
    }

    private func consentChanged(_ state: FoodConsentModel.State) {
        guard state == .granted, let action = pending else { return }
        pending = nil
        sheet = nil
        // The consent sheet has to be gone before the next surface appears.
        Task {
            try? await Task.sleep(for: .milliseconds(400))
            run(action)
        }
    }

    private func loadPhoto(_ item: PhotosPickerItem?) {
        guard let item else { return }
        photoItem = nil
        Task {
            guard let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else { return }
            // The picker is still leaving; a sheet presented in the same moment would be dropped.
            try? await Task.sleep(for: .milliseconds(450))
            startPhoto(image)
        }
    }

    private func coverDismissed() {
        if let image = capturedImage {
            capturedImage = nil
            startPhoto(image)
        } else if let food = scannedFood {
            scannedFood = nil
            openEditor(for: food, source: .barcode)
        }
    }

    private func startPhoto(_ image: UIImage) {
        Task {
            // Downsizing a camera original blocks for a moment; keep the main thread free while it runs.
            let prepared = await Task.detached(priority: .userInitiated) { FoodImage.prepare(image) }.value
            guard let prepared else { return }
            sheet = .analyze(makeLaunch(source: .photo(jpeg: prepared.jpeg, thumbnail: prepared.thumbnail)))
        }
    }

    private func startText() {
        let launch = makeLaunch(source: .text)
        launch.model.description = description
        sheet = .analyze(launch)
    }

    private func openEditor(for food: PackagedFood, source: FoodAnalyzeModel.Source) {
        let analysis = FoodAnalyzeModel(food: food, source: source)
        analysis.meal = meal
        sheet = .analyze(AnalyzeLaunch(model: analysis))
    }

    private func makeLaunch(source: FoodAnalyzeModel.Source) -> AnalyzeLaunch {
        let analysis = FoodAnalyzeModel(source: source, service: container.coach?.food, locale: languageCode)
        analysis.meal = meal
        return AnalyzeLaunch(model: analysis)
    }

    // MARK: Presented surfaces

    @ViewBuilder
    private func sheetContent(_ sheet: Sheet) -> some View {
        switch sheet {
        case .promo:
            FoodProPromoView { self.sheet = nil }
        case .consent:
            FoodConsentView(model: consent) { if !consent.isGranted { pending = nil; self.sheet = nil } }
        case .manual:
            ManualFoodView(editing: nil, meal: meal, onSave: { await model.save($0) }, onClose: { self.sheet = nil })
        case .analyze(let launch):
            FoodAnalyzeView(
                model: launch.model,
                onSave: { input in
                    let saved = await model.save(input)
                    if saved { savedFromAnalysis = true }
                    return saved
                },
                onClose: {
                    self.sheet = nil
                    if savedFromAnalysis { savedFromAnalysis = false; onClose() }
                }
            )
            .onChange(of: launch.model.remaining) { _, left in if let left { model.analysesLeft = left } }
        }
    }

    @ViewBuilder
    private func coverContent(_ cover: Cover) -> some View {
        switch cover {
        case .camera:
            CameraPicker { image in
                capturedImage = image
                self.cover = nil
            }
            .ignoresSafeArea()
        case .scanner:
            ScanBarcodeView(
                service: container.packagedFoods,
                onFound: { food in
                    scannedFood = food
                    self.cover = nil
                },
                onClose: { self.cover = nil }
            )
        }
    }
}

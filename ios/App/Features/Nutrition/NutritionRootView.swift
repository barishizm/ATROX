import DataKit
import DesignSystem
import SwiftUI

/// The nutrition screen: the day's calories and macros against the target, the meals, and the ways to add food.
struct NutritionRootView: View {
    @Environment(AppContainer.self) private var container
    @Environment(\.locale) private var locale
    @State private var model: NutritionModel?
    @State private var consent: FoodConsentModel?
    @State private var sheet: NutritionSheet?
    @State private var tab: NutritionTab = .diary
    @State private var summaryHeight: CGFloat = 0
    @State private var pageID: DiaryPage? = .summary
    @State private var showsCalendar = false
    @State private var showsQuiz = false
    @State private var detailMeal: MealType?
    @State private var unavailable = false

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
        .dsGlassSurfaces()
        .background(NutritionBackdrop().ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .task { await prepare() }
        .task(id: container.dataRevision) { await model?.load() }
        .sheet(item: $sheet) { sheet in sheetContent(sheet) }
        .fullScreenCover(isPresented: $showsQuiz) {
            if let model, let profile = model.profile {
                NutritionOnboardingView(model: model, profile: profile) { showsQuiz = false }
            }
        }
        .sheet(isPresented: $showsCalendar) {
            NutritionCalendarSheet(selection: model?.day ?? Date()) { picked in Task { await model?.select(day: picked) } }
        }
        .navigationDestination(item: $detailMeal) { meal in
            if let model {
                MealDetailView(model: model, meal: meal, onAdd: { sheet = .addFood(meal) }, onEdit: { sheet = .manual($0) })
            }
        }
        .accessibilityIdentifier("nutrition-root")
    }

    // MARK: Content

    private func content(_ model: NutritionModel) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            NutritionTabPicker(selection: $tab)
                .padding(.horizontal, Spacing.md)
            switch tab {
            case .diary: pager(model)
            case .recipes:
                EmptyState(systemImage: "book.closed", title: "nutrition.recipes.empty.title", message: "nutrition.recipes.empty.message")
                    .frame(maxHeight: .infinity).accessibilityIdentifier("nutrition-recipes")
            }
        }
        // Pinned above the pages; they slide under a black, slightly translucent fade.
        .safeAreaInset(edge: .top, spacing: 0) {
            NutritionHeader(title: dayTitle(model), shortTitle: shortDayTitle(model), streak: model.streak, onCalendar: { showsCalendar = true }) { optionsMenu }
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.xs)
                .background {
                    LinearGradient(colors: [.black, .black.opacity(0.9), .black.opacity(0.6)], startPoint: .top, endPoint: .bottom)
                        .ignoresSafeArea(edges: .top)
                }
        }
    }

    /// The diary does not scroll down as one long page: swipe sideways from the summary to water, fasting and notes.
    private var page: DiaryPage { pageID ?? .summary }

    @ViewBuilder
    private func pager(_ model: NutritionModel) -> some View {
        if model.isLoading {
            LoadingState()
        } else {
            do {
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 0) {
                        ForEach(DiaryPage.allCases) { page in
                            ScrollView {
                                pageContent(page, model)
                                    .padding(.horizontal, Spacing.md)
                                    .padding(.top, Spacing.xs)
                                    .padding(.bottom, Spacing.md)
                            }
                            .scrollBounceBehavior(.basedOnSize)
                            .refreshable { await model.load() }
                            .containerRelativeFrame(.horizontal)
                            .id(page)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.paging)
                .scrollPosition(id: $pageID)
                .scrollIndicators(.hidden)
            }
        }
    }

    @ViewBuilder
    private func pageContent(_ page: DiaryPage, _ model: NutritionModel) -> some View {
        VStack(spacing: Spacing.sm) {
            switch page {
            case .summary: summaryPage(model)
            case .water: WaterCard(model: model, minHeight: summaryHeight)
            case .fasting: FastingCard(model: model, minHeight: summaryHeight, onStart: { sheet = .fastPlan })
            case .notes: NotesCard(model: model, minHeight: summaryHeight, onEdit: { sheet = .note })
            }
            // Travels with the card instead of staying pinned to the screen.
            HStack(spacing: Spacing.xs) {
                ForEach(DiaryPage.allCases) { item in
                    Circle().fill(item == page ? DSColor.textPrimary : DSColor.textTertiary).frame(width: 7, height: 7)
                }
            }
            .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private func summaryPage(_ model: NutritionModel) -> some View {
        Card(padding: 0) {
            VStack(spacing: 0) {
                NutritionSummaryCard(model: model, onTarget: { sheet = .target }, embedded: true)
                Divider().overlay(DSColor.separator)
                NutritionMealsCard(model: model, onOpen: { detailMeal = $0 }, onAdd: { sheet = .addFood($0) }, embedded: true)
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { summaryHeight = $0 }
        if let left = model.analysesLeft { quotaChip(left) }
    }

    /// "Saturday, November 21"; the header falls back to `shortDayTitle` ("Sat, Nov 21") when this does not fit.
    private func dayTitle(_ model: NutritionModel) -> Text {
        Text(verbatim: model.day.formatted(.dateTime.weekday(.wide).month(.wide).day().locale(locale)))
    }

    private func shortDayTitle(_ model: NutritionModel) -> Text {
        Text(verbatim: model.day.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().locale(locale)))
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
            Button { sheet = .sources } label: { Label("nutrition.sources.link", systemImage: "books.vertical") }
            if model?.profile != nil { Button { showsQuiz = true } label: { Label("nutrition.quiz.restart", systemImage: "list.bullet.clipboard") } }
            if consent?.isGranted == true {
                Button(role: .destructive) { Task { await consent?.decline() } } label: { Label("nutrition.consent.withdraw", systemImage: "hand.raised") }
            }
        } label: { Image(systemName: "ellipsis").font(.title3.weight(.semibold)) }
        .accessibilityLabel(Text("nutrition.options"))
    }

    // MARK: Sheets

    @ViewBuilder
    private func sheetContent(_ sheet: NutritionSheet) -> some View {
        switch sheet {
        case .addFood(let meal):
            if let model, let consent {
                AddFoodView(model: model, consent: consent, meal: meal, onClose: { self.sheet = nil })
            }
        case .manual(let entry):
            ManualFoodView(
                editing: entry, meal: nil,
                onSave: { input in
                    if let entry { return await model?.update(id: entry.id, with: input) ?? false }
                    return await model?.save(input) ?? false
                },
                onClose: { self.sheet = nil }
            )
        case .target:
            NutritionTargetSetupView(
                profile: model?.profile, current: model?.target, onSave: { await model?.setTarget($0) ?? false }, onClose: { self.sheet = nil }
            )
        case .activity: ActivitySheet { name, minutes, kcal in await model?.addActivity(name: name, minutes: minutes, kcal: kcal) ?? false }
        case .steps: StepsSheet { await model?.addSteps($0) ?? false }
        case .note: NoteSheet(existing: model?.note) { await model?.saveNote(mood: $0, text: $1) ?? false }
        case .fastPlan: FastPlanSheet { await model?.startFast(hours: $0, label: $1) ?? false }
        case .goalWeight:
            GoalWeightSheet(
                title: "nutrition.weight.goal.title", field: "nutrition.weight.goal.field", unit: model?.profile?.weightUnit ?? .kilograms,
                current: model?.goalWeightKg
            ) { await model?.setGoalWeight(kg: $0) ?? false }
        case .weightEntry:
            GoalWeightSheet(
                title: "nutrition.weight.title", field: "nutrition.weight.field", unit: model?.profile?.weightUnit ?? .kilograms, current: nil
            ) { await model?.logWeight(kg: $0) ?? false }
        case .weightProgress: if let model { WeightProgressSheet(model: model) }
        case .sources: NutritionSourcesSheet()
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
        // First visit: a target is worked out from a short quiz instead of an empty ring.
        if made.target == nil, made.profile != nil, !NutritionPreferences.quizFinished(userId: made.userId) { showsQuiz = true }
    }
}

/// The sideways pages of the diary, in swipe order.
enum DiaryPage: String, CaseIterable, Identifiable {
    case summary, water, fasting, notes
    var id: String { rawValue }
}

struct AnalyzeLaunch: Identifiable {
    let id = UUID()
    let model: FoodAnalyzeModel
}

enum NutritionSheet: Identifiable {
    case addFood(MealType)
    case manual(FoodEntrySnapshot?)
    case target
    case activity, steps, note, fastPlan, goalWeight, weightEntry, weightProgress, sources

    var id: String {
        switch self {
        case .addFood(let meal): "add-food-\(meal.rawValue)"
        case .manual(let entry): "manual-\(entry?.id.uuidString ?? "new")"
        case .target: "target"
        case .activity: "activity"
        case .steps: "steps"
        case .note: "note"
        case .fastPlan: "fast-plan"
        case .goalWeight: "goal-weight"
        case .weightEntry: "weight-entry"
        case .weightProgress: "weight-progress"
        case .sources: "sources"
        }
    }
}

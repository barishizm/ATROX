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
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                NutritionHeader(title: dayTitle(model), shortTitle: shortDayTitle(model), streak: model.streak, onCalendar: { showsCalendar = true }) { optionsMenu }
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
            Text("nutrition.summary.title").font(DSFont.title).foregroundStyle(DSColor.textPrimary)
            Card(padding: 0) {
                VStack(spacing: 0) {
                    NutritionSummaryCard(model: model, onTarget: { sheet = .target }, embedded: true)
                    Divider().overlay(DSColor.separator)
                    NutritionMealsCard(model: model, onOpen: { detailMeal = $0 }, onAdd: { sheet = .addFood($0) }, embedded: true)
                }
            }
            if let left = model.analysesLeft { quotaChip(left) }
            DiarySectionTitle(title: "nutrition.water.section")
            WaterCard(model: model)
            DiarySectionTitle(title: "nutrition.weight.section")
            WeightCard(model: model, onGoal: { sheet = .goalWeight }, onEntry: { sheet = .weightEntry }, onProgress: { sheet = .weightProgress })
            DiarySectionTitle(title: "nutrition.fasting.section")
            FastingCard(model: model, onStart: { sheet = .fastPlan })
            DiarySectionTitle(title: "nutrition.activities.section")
            ActivitiesCard(model: model, onSteps: { sheet = .steps }, onAdd: { sheet = .activity })
            DiarySectionTitle(title: "nutrition.notes.section")
            NotesCard(model: model, onEdit: { sheet = .note })
            Button { sheet = .sources } label: { Text("nutrition.sources.link").font(DSFont.callout).foregroundStyle(DSColor.accent) }
                .frame(maxWidth: .infinity, minHeight: HitTarget.minimum)
        }
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

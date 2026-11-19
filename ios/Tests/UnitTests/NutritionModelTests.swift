import CoachKit
import DataKit
import Foundation
import Testing

@testable import ATROX

private struct StubFood: FoodAnalyzeService {
    let result: Result<FoodAnalysis, FoodAnalyzeError>
    func analyze(_ input: FoodAnalyzeInput, locale: String) async throws -> FoodAnalysis { try result.get() }
}

private let analysis = FoodAnalysis(
    mealName: "Chicken and rice",
    items: [
        FoodAnalysisItem(name: "Chicken", grams: 150, calories: 248, proteinG: 46, carbsG: 0, fatG: 5.4),
        FoodAnalysisItem(name: "Rice", grams: 200, calories: 260, proteinG: 5, carbsG: 56, fatG: 0.5),
    ],
    remaining: 2, limit: 3
)

@MainActor
struct FoodAnalyzeModelTests {
    @Test func photoAnalysisFillsTheEditor() async {
        let model = FoodAnalyzeModel(source: .photo(jpeg: Data([1]), thumbnail: Data([2])), service: StubFood(result: .success(analysis)), locale: "en")
        #expect(model.phase == .analyzing)
        await model.analyze()
        #expect(model.phase == .result)
        #expect(model.mealName == "Chicken and rice")
        #expect(model.items.count == 2)
        #expect(model.remaining == 2 && model.limit == 3)
        let input = model.makeInput()
        #expect(input.source == .photo && input.thumbnail == Data([2]))
        #expect(Int(input.calories.rounded()) == 508)
    }

    @Test func editingGramsScalesTheFoodAndRemovingDropsIt() async {
        let model = FoodAnalyzeModel(source: .photo(jpeg: Data([1]), thumbnail: nil), service: StubFood(result: .success(analysis)), locale: "en")
        await model.analyze()
        let rice = model.items[1]
        model.setGrams(100, for: rice.id)
        #expect(model.items[1].calories == 130)
        model.setGrams(0, for: rice.id) // clamped to 1 g, never zero
        #expect(model.items[1].grams == 1)
        model.remove(model.items[0].id)
        #expect(model.items.count == 1)
    }

    @Test func serverErrorsBecomeFailedPhases() async {
        for error in [FoodAnalyzeError.quotaExceeded(limit: 3), .notFood, .offline] {
            let model = FoodAnalyzeModel(source: .photo(jpeg: Data([1]), thumbnail: nil), service: StubFood(result: .failure(error)), locale: "en")
            await model.analyze()
            #expect(model.phase == .failed(error))
        }
    }

    @Test func noServiceMeansUnavailableNotACrash() async {
        let model = FoodAnalyzeModel(source: .photo(jpeg: Data([1]), thumbnail: nil), service: nil, locale: "en")
        await model.analyze()
        #expect(model.phase == .failed(.unavailable))
    }

    @Test func textSourceWaitsForADescriptionAndIgnoresShortOnes() async {
        let model = FoodAnalyzeModel(source: .text, service: StubFood(result: .success(analysis)), locale: "tr")
        #expect(model.phase == .input)
        model.description = "a"
        await model.analyze()
        #expect(model.phase == .input)
        model.description = "tavuk pilav"
        await model.analyze()
        #expect(model.phase == .result)
        #expect(model.makeInput().source == .text)
    }

    @Test func aScannedProductGoesStraightToTheEditor() {
        let food = PackagedFood(
            barcode: "3017620422003",
            name: "Spread",
            caloriesPer100g: 539,
            proteinPer100g: 6.3,
            carbsPer100g: 57.5,
            fatPer100g: 30.9,
            servingGrams: 15
        )
        let model = FoodAnalyzeModel(food: food)
        #expect(model.phase == .result)
        #expect(model.items.first?.grams == 15)
        #expect(model.makeInput().source == .barcode)
        #expect(model.canSave)
    }

    @Test func cannotSaveAnEmptyMeal() {
        let model = FoodAnalyzeModel(source: .text, service: nil, locale: "en")
        #expect(!model.canSave)
    }
}

@MainActor
struct NutritionModelTests {
    private let user = UUID()
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func make(now: Date = Date(timeIntervalSince1970: 1_800_000_000)) throws -> NutritionModel {
        let container = try DataStore.inMemory()
        let repository = SwiftDataNutritionRepository(modelContainer: container)
        let profile = NutritionProfile(sex: .male, ageYears: 30, heightCm: 180, weightKg: 80, goal: .muscleGain, weeklyFrequency: 4)
        return NutritionModel(userId: user, repository: repository, calendar: calendar, now: { now }) { profile }
    }

    private func entry(_ name: String, kcal: Double, at date: Date) -> FoodEntryInput {
        FoodEntryInput(eatenAt: date, meal: .lunch, name: name, calories: kcal, proteinG: 20, carbsG: 30, fatG: 10, source: .manual)
    }

    @Test func savedFoodShowsUpInTheDayTotalsAndLeft() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let model = try make(now: now)
        await model.load()
        #expect(model.target == nil && model.caloriesLeft == nil)
        let auto = try #require(model.profile?.autoTarget)
        await model.setTarget(NutritionTargetInput(mode: .auto, values: auto, activity: .moderate))
        #expect(await model.save(entry("Oats", kcal: 400, at: now)))
        #expect(await model.save(entry("Chicken", kcal: 600, at: now.addingTimeInterval(-600))))
        #expect(model.summary.calories == 1000)
        #expect(model.caloriesLeft == Double(auto.calories) - 1000)
        #expect(model.entries(for: .lunch).count == 2)
    }

    @Test func deleteRemovesTheEntry() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let model = try make(now: now)
        await model.load()
        _ = await model.save(entry("Oats", kcal: 400, at: now))
        let id = try #require(model.summary.entries.first?.id)
        await model.delete(id: id)
        #expect(model.summary.entries.isEmpty)
    }

    @Test func dayNavigationStopsAtToday() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let model = try make(now: now)
        await model.load()
        #expect(model.isToday && !model.canGoForward)
        await model.shiftDay(by: 1)
        #expect(model.isToday, "cannot go into the future")
        await model.shiftDay(by: -1)
        #expect(!model.isToday && model.canGoForward)
        await model.goToToday()
        #expect(model.isToday)
    }

    @Test func foodSavedForAnotherDayJumpsToThatDay() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let model = try make(now: now)
        await model.load()
        let yesterday = now.addingTimeInterval(-86_400)
        #expect(await model.save(entry("Late snack", kcal: 300, at: yesterday)))
        #expect(!model.isToday)
        #expect(model.summary.calories == 300)
    }

    @Test func invalidEntryIsNotSaved() async throws {
        let model = try make()
        await model.load()
        #expect(await model.save(entry("", kcal: 100, at: Date())) == false)
    }

    @Test func profileWithoutWeightHasNoAutoTarget() {
        let profile = NutritionProfile(sex: .female, ageYears: 25, heightCm: 165, weightKg: nil, goal: .fatLoss, weeklyFrequency: 3)
        #expect(profile.autoTarget == nil)
        #expect(profile.activity == .moderate)
    }
}

struct FoodConsentStateTests {
    @Test func statusMapsToState() {
        #expect(FoodConsentModel.state(for: .granted) == .granted)
        #expect(FoodConsentModel.state(for: .declined) == .declined)
        #expect(FoodConsentModel.state(for: .notAsked) == .needed)
        #expect(FoodConsentModel.state(for: .outdated(previous: true)) == .needed)
    }
}

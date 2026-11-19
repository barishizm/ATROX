@testable import DataKit
import Foundation
import Testing

@Suite struct NutritionTargetCalculatorTests {
    private func input(sex: Sex = .male, age: Int = 30, height: Double = 180, weight: Double = 80, goal: Goal, activity: ActivityLevel = .moderate)
        -> NutritionTargetCalculator.Input {
        .init(sex: sex, ageYears: age, heightCm: height, weightKg: weight, goal: goal, activity: activity)
    }

    @Test func mifflinStJeorMale() {
        // 10*80 + 6.25*180 - 5*30 + 5 = 1780
        #expect(NutritionTargetCalculator.basalRate(input(goal: .generalHealth)) == 1780)
        #expect(NutritionTargetCalculator.basalRate(input(sex: .female, goal: .generalHealth)) == 1614)
    }

    @Test func goalAdjustsCalories() {
        let maintain = NutritionTargetCalculator.target(for: input(goal: .generalHealth)).calories
        let gain = NutritionTargetCalculator.target(for: input(goal: .muscleGain)).calories
        let cut = NutritionTargetCalculator.target(for: input(goal: .fatLoss)).calories
        #expect(maintain == 2760) // 1780 * 1.55 = 2759 → 2760
        #expect(gain > maintain)
        #expect(cut < maintain)
        #expect(cut == 2350) // 2759 * 0.85 = 2345 → 2350 (rounded to 10)
    }

    @Test func macrosAddUpToTheCalories() {
        let target = NutritionTargetCalculator.target(for: input(goal: .muscleGain))
        let sum = target.proteinG * 4 + target.carbsG * 4 + target.fatG * 9
        #expect(abs(sum - target.calories) <= 12)
        #expect(target.proteinG == 144) // 1.8 g/kg × 80
    }

    @Test func fatLossRaisesProtein() {
        #expect(NutritionTargetCalculator.target(for: input(goal: .fatLoss)).proteinG == 160) // 2.0 g/kg
    }

    @Test func neverBelowTheSafetyFloor() {
        let small = input(sex: .female, age: 60, height: 150, weight: 45, goal: .fatLoss, activity: .sedentary)
        #expect(NutritionTargetCalculator.target(for: small).calories == 1200)
        let smallMale = input(sex: .male, age: 70, height: 155, weight: 48, goal: .fatLoss, activity: .sedentary)
        #expect(NutritionTargetCalculator.target(for: smallMale).calories == 1500)
    }

    @Test func minorsNeverGetADeficit() {
        let teen = input(age: 16, weight: 65, goal: .fatLoss)
        let maintain = input(age: 16, weight: 65, goal: .generalHealth)
        #expect(NutritionTargetCalculator.target(for: teen).calories == NutritionTargetCalculator.target(for: maintain).calories)
    }

    @Test func activityFollowsTrainingFrequency() {
        #expect(ActivityLevel.from(weeklyFrequency: 0) == .sedentary)
        #expect(ActivityLevel.from(weeklyFrequency: 2) == .light)
        #expect(ActivityLevel.from(weeklyFrequency: 4) == .moderate)
        #expect(ActivityLevel.from(weeklyFrequency: 6) == .active)
        #expect(ActivityLevel.from(weeklyFrequency: 7) == .veryActive)
    }
}

@Suite struct NutritionRepositoryTests {
    private let clock = TestClock()
    private func makeRepo() throws -> SwiftDataNutritionRepository {
        SwiftDataNutritionRepository(modelContainer: try DataStore.inMemory(), clock: clock.closure)
    }

    private func entry(_ name: String = "Oats", at date: Date, kcal: Double = 300) -> FoodEntryInput {
        FoodEntryInput(eatenAt: date, meal: .breakfast, name: name, calories: kcal, proteinG: 10, carbsG: 50, fatG: 6, source: .manual)
    }

    @Test func addStoresPendingRowAndItemsRoundTrip() async throws {
        let repo = try makeRepo()
        let item = FoodItemDetail(name: "Rice", grams: 200, calories: 260, proteinG: 5, carbsG: 56, fatG: 0.5)
        let input = FoodEntryInput(eatenAt: Date(), meal: .lunch, name: "Rice bowl", source: .photo, items: [item], thumbnail: Data([1, 2]))
        let saved = try await repo.add(input, userId: testUser)
        #expect(saved.syncState == .pending)
        #expect(saved.input.calories == 260)
        #expect(saved.input.items == [item])
        #expect(saved.input.thumbnail == Data([1, 2]))
    }

    @Test func entriesFilterByDayAndUserAndHideDeleted() async throws {
        let repo = try makeRepo()
        let day = Date(timeIntervalSince1970: 1_800_000_000)
        let a = try await repo.add(entry("A", at: day), userId: testUser)
        _ = try await repo.add(entry("B", at: day.addingTimeInterval(3600)), userId: testUser)
        _ = try await repo.add(entry("Other day", at: day.addingTimeInterval(86_400 * 2)), userId: testUser)
        _ = try await repo.add(entry("Other user", at: day), userId: otherUser)
        let found = try await repo.entries(userId: testUser, from: day.addingTimeInterval(-60), to: day.addingTimeInterval(86_400))
        #expect(found.map(\.input.name) == ["A", "B"])
        try await repo.delete(id: a.id)
        #expect(try await repo.entries(userId: testUser, from: day.addingTimeInterval(-60), to: day.addingTimeInterval(86_400)).count == 1)
    }

    @Test func updateMarksPendingAndKeepsThumbnailWhenNoneGiven() async throws {
        let repo = try makeRepo()
        let saved = try await repo.add(FoodEntryInput(eatenAt: Date(), meal: .snack, name: "Bar", calories: 200, source: .manual, thumbnail: Data([9])), userId: testUser)
        clock.advance(by: 60)
        let updated = try await repo.update(id: saved.id, with: entry("Bar", at: saved.input.eatenAt, kcal: 250))
        #expect(updated.input.calories == 250)
        #expect(updated.input.thumbnail == Data([9]))
        #expect(updated.updatedAt > saved.updatedAt)
    }

    @Test func rejectsInvalidValues() async throws {
        let repo = try makeRepo()
        await #expect(throws: DataError.self) { try await repo.add(entry(" ", at: Date()), userId: testUser) }
        await #expect(throws: DataError.self) { try await repo.add(entry("X", at: Date(), kcal: -1), userId: testUser) }
        await #expect(throws: DataError.self) { try await repo.add(entry("X", at: Date(), kcal: 30_000), userId: testUser) }
        await #expect(throws: DataError.notFound) { try await repo.delete(id: UUID()) }
    }

    @Test func targetUpsertKeepsOneRow() async throws {
        let repo = try makeRepo()
        #expect(try await repo.target(userId: testUser) == nil)
        let first = NutritionTargetInput(mode: .auto, values: .init(calories: 2400, proteinG: 150, carbsG: 280, fatG: 65), activity: .moderate)
        try await repo.setTarget(first, userId: testUser)
        var second = first
        second.mode = .manual
        second.values.calories = 2200
        try await repo.setTarget(second, userId: testUser)
        #expect(try await repo.target(userId: testUser) == second)
        #expect(try await repo.target(userId: otherUser) == nil)
        await #expect(throws: DataError.self) {
            try await repo.setTarget(NutritionTargetInput(mode: .manual, values: .init(calories: 300, proteinG: 1, carbsG: 1, fatG: 1), activity: .light), userId: testUser)
        }
    }

    @Test func targetIdIsDeterministicPerUser() {
        #expect(NutritionTarget.id(userId: testUser) == NutritionTarget.id(userId: testUser))
        #expect(NutritionTarget.id(userId: testUser) != NutritionTarget.id(userId: otherUser))
    }
}

@Suite struct NutritionDayTests {
    @Test func summarizeSumsOneCalendarDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let noon = Date(timeIntervalSince1970: 1_799_971_200 + 43_200) // 2026-… 00:00 UTC + 12 h
        func snap(_ kcal: Double, at date: Date) -> FoodEntrySnapshot {
            FoodEntrySnapshot(userId: testUser, input: FoodEntryInput(eatenAt: date, meal: .lunch, name: "x", calories: kcal, proteinG: 10, carbsG: 20, fatG: 5, source: .manual))
        }
        let day = NutritionDay.summarize([snap(500, at: noon), snap(300, at: noon.addingTimeInterval(3600)), snap(900, at: noon.addingTimeInterval(86_400))], on: noon, calendar: calendar)
        #expect(day.calories == 800)
        #expect(day.proteinG == 20)
        #expect(day.entries.count == 2)
        #expect(NutritionDay.summarize([], on: noon, calendar: calendar) == .empty)
    }

    @Test func scalingKeepsRatios() {
        let item = FoodItemDetail(name: "Rice", grams: 100, calories: 130, proteinG: 2.7, carbsG: 28, fatG: 0.3)
        let doubled = item.scaled(toGrams: 200)
        #expect(doubled.calories == 260)
        #expect(doubled.carbsG == 56)
    }
}

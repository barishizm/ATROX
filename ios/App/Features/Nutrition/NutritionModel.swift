import DataKit
import Foundation
import Observation

/// What the automatic target needs from the profile and the latest weigh-in.
struct NutritionProfile: Sendable, Equatable {
    var sex: Sex
    var ageYears: Int
    var heightCm: Double
    var weightKg: Double?
    var goal: Goal
    var weeklyFrequency: Int
    var weightUnit: WeightUnit = .kilograms

    /// The automatic target; nil until there is a weight.
    var autoTarget: NutritionTargetValues? {
        guard let weightKg else { return nil }
        return NutritionTargetCalculator.target(for: .init(
            sex: sex, ageYears: ageYears, heightCm: heightCm, weightKg: weightKg, goal: goal,
            activity: ActivityLevel.from(weeklyFrequency: weeklyFrequency)
        ))
    }

    var activity: ActivityLevel { ActivityLevel.from(weeklyFrequency: weeklyFrequency) }
}

/// The nutrition screen: one day's entries against the user's target.
@MainActor
@Observable
final class NutritionModel {
    let userId: UUID
    private(set) var day: Date
    private(set) var summary: NutritionDay = .empty
    private(set) var target: NutritionTargetInput?
    var profile: NutritionProfile?
    /// The shown day's water and note logs, oldest first.
    var dayLogs: [DiaryLogSnapshot] = []
    /// Recent fasts, newest first.
    var fasts: [DiaryLogSnapshot] = []
    /// Weigh-ins, newest day first.
    var weights: [MeasurementSnapshot] = []
    /// Start-of-day of every day with food logged, for the streak.
    private(set) var trackedDays: Set<Date> = []
    private(set) var isLoading = true
    private(set) var failed = false
    /// AI analyses left today, known after the first analysis (the server counts).
    var analysesLeft: Int?

    @ObservationIgnored private let repository: any NutritionRepository
    @ObservationIgnored let diary: (any DiaryRepository)?
    @ObservationIgnored let measurementRepository: (any MeasurementRepository)?
    @ObservationIgnored let loadProfile: @Sendable () async -> NutritionProfile?
    @ObservationIgnored let calendar: Calendar
    @ObservationIgnored let now: @Sendable () -> Date

    init(
        userId: UUID, repository: any NutritionRepository, diary: (any DiaryRepository)? = nil,
        measurements: (any MeasurementRepository)? = nil,
        calendar: Calendar = .current, now: @escaping @Sendable () -> Date = { Date() },
        loadProfile: @escaping @Sendable () async -> NutritionProfile?
    ) {
        self.userId = userId
        self.repository = repository
        self.diary = diary
        self.measurementRepository = measurements
        self.calendar = calendar
        self.now = now
        self.loadProfile = loadProfile
        day = now()
    }

    var isToday: Bool { calendar.isDate(day, inSameDayAs: now()) }
    var canGoForward: Bool { !isToday }

    /// Days in a row with food logged, ending today (or yesterday while today is still open).
    var streak: Int { NutritionStreak.current(trackedDays: trackedDays, now: now(), calendar: calendar) }

    /// Calories the day's target allows per meal; nil without a target.
    var mealBudgets: [MealType: Int]? { target.map { MealBudget.calories(total: $0.values.calories) } }

    func calories(for meal: MealType) -> Double { entries(for: meal).reduce(0) { $0 + $1.input.calories } }

    /// Calories left to the target (negative = over); nil without a target.
    var caloriesLeft: Double? { target.map { Double($0.values.calories) - summary.calories } }

    /// Progress of the day toward the calorie target, 0…∞.
    var calorieProgress: Double {
        guard let target, target.values.calories > 0 else { return 0 }
        return summary.calories / Double(target.values.calories)
    }

    func entries(for meal: MealType) -> [FoodEntrySnapshot] { summary.entries.filter { $0.input.meal == meal } }

    func load() async {
        failed = false
        profile = await loadProfile()
        await reloadDiary()
        do {
            target = try await repository.target(userId: userId)
            try await reloadDay()
            try await reloadTrackedDays()
        } catch {
            failed = true
        }
        isLoading = false
    }

    func shiftDay(by days: Int) async {
        guard let next = calendar.date(byAdding: .day, value: days, to: day), next <= now() || days < 0 else { return }
        day = next
        try? await reloadDay()
    }

    func select(day newDay: Date) async {
        day = min(newDay, now())
        try? await reloadDay()
    }

    func goToToday() async {
        day = now()
        try? await reloadDay()
    }

    func save(_ input: FoodEntryInput) async -> Bool {
        do {
            _ = try await repository.add(input, userId: userId)
            // Show the day the food was eaten on.
            if !calendar.isDate(input.eatenAt, inSameDayAs: day) { day = input.eatenAt }
            try await reloadDay()
            try await reloadTrackedDays()
            return true
        } catch {
            return false
        }
    }

    func update(id: UUID, with input: FoodEntryInput) async -> Bool {
        do {
            _ = try await repository.update(id: id, with: input)
            try await reloadDay()
            try await reloadTrackedDays()
            return true
        } catch {
            return false
        }
    }

    func delete(id: UUID) async {
        try? await repository.delete(id: id)
        try? await reloadDay()
        try? await reloadTrackedDays()
    }

    @discardableResult
    func setTarget(_ input: NutritionTargetInput) async -> Bool {
        do {
            target = try await repository.setTarget(input, userId: userId)
            return true
        } catch {
            return false
        }
    }

    private func reloadDay() async throws {
        let start = calendar.startOfDay(for: day)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return }
        let entries = try await repository.entries(userId: userId, from: start, to: end)
        summary = NutritionDay.summarize(entries, on: day, calendar: calendar)
        await reloadDayLogs()
    }

    /// Logging history is read a year back; a streak longer than that stops growing on screen.
    /// Only after loading and writing: moving between days does not change it. Reads dates only, no thumbnails.
    private func reloadTrackedDays() async throws {
        let today = calendar.startOfDay(for: now())
        guard let from = calendar.date(byAdding: .day, value: -365, to: today), let to = calendar.date(byAdding: .day, value: 1, to: today) else { return }
        let dates = try await repository.eatenDates(userId: userId, from: from, to: to)
        trackedDays = NutritionStreak.trackedDays(dates, calendar: calendar)
    }
}

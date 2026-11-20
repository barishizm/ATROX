import DataKit
import Foundation

/// What the model needs from Apple Health, kept as closures so tests can stub it.
struct NutritionHealth: Sendable {
    /// Whether the user already pressed "Connect" on this device.
    var isConnected: @Sendable () -> Bool
    /// Asks for permission to read steps and remembers the answer.
    var connect: @Sendable () async -> Bool
    var steps: @Sendable (Date) async -> Double?
}

/// Water, activities, steps, notes, fasting and weight of the nutrition diary.
extension NutritionModel {
    static let kcalPerStep = 0.04
    static let glassMl = 250.0
    static let moods = ["great", "good", "okay", "bad", "awful"]

    // MARK: Derived

    private func logs(_ kind: DiaryLogKind) -> [DiaryLogSnapshot] { dayLogs.filter { $0.input.kind == kind } }

    var waterMl: Double { logs(.water).reduce(0) { $0 + $1.input.amount } }

    /// 35 ml per kg of body weight in whole glasses, 2 L without a weight.
    var waterGoalMl: Double {
        guard let kg = weightKg else { return 2000 }
        return max((kg * 35 / Self.glassMl).rounded() * Self.glassMl, 1500)
    }

    var activities: [DiaryLogSnapshot] { logs(.activity) }

    var manualSteps: Double { logs(.steps).reduce(0) { $0 + $1.input.quantity } }

    /// Health's count when connected, otherwise what the user typed in.
    var totalSteps: Double { stepsConnected ? (healthSteps ?? 0) : manualSteps }

    /// Calories burned by activities and steps on the shown day.
    var burnedCalories: Double {
        let moved = activities.reduce(0) { $0 + $1.input.amount }
        return moved + (stepsConnected ? (healthSteps ?? 0) * Self.kcalPerStep : logs(.steps).reduce(0) { $0 + $1.input.amount })
    }

    var note: DiaryLogSnapshot? { logs(.note).last }

    var activeFast: DiaryLogSnapshot? { fasts.first { $0.input.endedAt == nil } }

    var lastFinishedFast: DiaryLogSnapshot? { fasts.first { $0.input.endedAt != nil } }

    var weightKg: Double? { weights.first?.input.weightKg ?? profile?.weightKg }

    // MARK: Loading

    func reloadDiary() async {
        if let measurementRepository { weights = (try? await measurementRepository.all(userId: userId)) ?? [] }
        guard let diary else { return }
        goalWeightKg = try? await diary.latest(userId: userId, kind: .goalWeight)?.input.amount
        let today = calendar.startOfDay(for: now())
        guard let from = calendar.date(byAdding: .day, value: -60, to: today),
              let to = calendar.date(byAdding: .day, value: 2, to: today) else { return }
        fasts = ((try? await diary.logs(userId: userId, kinds: [.fast], from: from, to: to)) ?? []).sorted { $0.input.at > $1.input.at }
    }

    func reloadDayLogs() async {
        let start = calendar.startOfDay(for: day)
        if let diary, let end = calendar.date(byAdding: .day, value: 1, to: start) {
            dayLogs = (try? await diary.logs(userId: userId, kinds: [.water, .activity, .steps, .note], from: start, to: end)) ?? []
        }
        healthSteps = stepsConnected ? await health?.steps(day) : nil
    }

    // MARK: Writing

    /// When a log made on the shown day happened: now for today, noon for a past day.
    private func moment() -> Date {
        isToday ? now() : (calendar.date(bySettingHour: 12, minute: 0, second: 0, of: day) ?? day)
    }

    @discardableResult
    private func write(_ input: DiaryLogInput) async -> Bool {
        guard let diary else { return false }
        do {
            _ = try await diary.add(input, userId: userId)
            await reloadDiary()
            await reloadDayLogs()
            return true
        } catch {
            return false
        }
    }

    func addWater(ml: Double = glassMl) async { await write(DiaryLogInput(kind: .water, at: moment(), amount: ml)) }

    func removeWater() async {
        guard let last = logs(.water).last else { return }
        await deleteLog(id: last.id)
    }

    func deleteLog(id: UUID) async {
        try? await diary?.delete(id: id)
        await reloadDiary()
        await reloadDayLogs()
    }

    func addActivity(name: String, minutes: Double, kcal: Double) async -> Bool {
        await write(DiaryLogInput(kind: .activity, at: moment(), amount: kcal, quantity: minutes, label: name))
    }

    func addSteps(_ steps: Double) async -> Bool {
        await write(DiaryLogInput(kind: .steps, at: moment(), amount: (steps * Self.kcalPerStep).rounded(), quantity: steps))
    }

    func connectSteps() async {
        guard let health, await health.connect() else { return }
        stepsConnected = true
        await reloadDayLogs()
    }

    func saveNote(mood: String, text: String) async -> Bool {
        let input = DiaryLogInput(kind: .note, at: note?.input.at ?? moment(), label: mood, text: text.trimmingCharacters(in: .whitespacesAndNewlines))
        guard let diary else { return false }
        do {
            if let existing = note { _ = try await diary.update(id: existing.id, with: input) } else { _ = try await diary.add(input, userId: userId) }
            await reloadDayLogs()
            return true
        } catch {
            return false
        }
    }

    func startFast(hours: Double, label: String) async -> Bool {
        guard activeFast == nil else { return false }
        return await write(DiaryLogInput(kind: .fast, at: now(), quantity: hours, label: label))
    }

    func endFast() async {
        guard let diary, let active = activeFast else { return }
        var input = active.input
        input.endedAt = max(now(), input.at)
        _ = try? await diary.update(id: active.id, with: input)
        await reloadDiary()
    }

    func setGoalWeight(kg: Double) async -> Bool {
        guard let diary else { return false }
        do {
            _ = try await diary.add(DiaryLogInput(kind: .goalWeight, at: now(), amount: kg), userId: userId)
            goalWeightKg = kg
            return true
        } catch {
            return false
        }
    }

    /// Changes today's weigh-in by `deltaKg`, starting from the latest known weight.
    func adjustWeight(by deltaKg: Double) async {
        guard let base = weightKg else { return }
        _ = await logWeight(kg: base + deltaKg)
    }

    /// Sets today's weigh-in (one per day: an existing one is updated).
    @discardableResult
    func logWeight(kg: Double) async -> Bool {
        guard let measurementRepository else { return false }
        let next = min(max((kg * 10).rounded() / 10, 20), 400)
        let input = MeasurementInput(date: now(), weightKg: next, bodyFatPct: weights.first?.input.bodyFatPct)
        do {
            if let latest = weights.first, calendar.isDate(latest.input.date, inSameDayAs: now()) {
                _ = try await measurementRepository.update(id: latest.id, with: MeasurementInput(
                    date: latest.input.date, weightKg: next, bodyFatPct: latest.input.bodyFatPct, source: latest.input.source
                ))
            } else {
                _ = try await measurementRepository.add(input, userId: userId)
            }
            await reloadDiary()
            profile = await loadProfile()
            return true
        } catch {
            return false
        }
    }

    func deleteWeight(id: UUID) async {
        try? await measurementRepository?.delete(id: id)
        await reloadDiary()
    }
}

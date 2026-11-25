import DataKit
import Foundation

/// Water, notes, fasting and weight of the nutrition diary.
extension NutritionModel {
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

    var note: DiaryLogSnapshot? { logs(.note).last }

    var activeFast: DiaryLogSnapshot? { fasts.first { $0.input.endedAt == nil } }

    var lastFinishedFast: DiaryLogSnapshot? { fasts.first { $0.input.endedAt != nil } }

    var weightKg: Double? { weights.first?.input.weightKg ?? profile?.weightKg }

    // MARK: Loading

    func reloadDiary() async {
        if let measurementRepository { weights = (try? await measurementRepository.all(userId: userId)) ?? [] }
        guard let diary else { return }
        let today = calendar.startOfDay(for: now())
        guard let from = calendar.date(byAdding: .day, value: -60, to: today),
              let to = calendar.date(byAdding: .day, value: 2, to: today) else { return }
        fasts = ((try? await diary.logs(userId: userId, kinds: [.fast], from: from, to: to)) ?? []).sorted { $0.input.at > $1.input.at }
    }

    func reloadDayLogs() async {
        let start = calendar.startOfDay(for: day)
        if let diary, let end = calendar.date(byAdding: .day, value: 1, to: start) {
            dayLogs = (try? await diary.logs(userId: userId, kinds: [.water, .note], from: start, to: end)) ?? []
        }
    }

    // MARK: Writing

    /// When a log made on the shown day happened: now for today, noon for a past day.
    func moment() -> Date {
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
            return true
        } catch {
            return false
        }
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
}

import DataKit
import Foundation
import Observation

/// The history list and calendar (P042): finished workouts newest first in pages, plus the month shown in the
/// calendar with its totals. Only a page, the month and nothing else is ever loaded, so 500+ workouts stay smooth.
@MainActor
@Observable
final class HistoryModel {
    static let pageSize = 30

    let context: HistoryContext
    private(set) var workouts: [WorkoutSnapshot] = []
    private(set) var hasMore = true
    private(set) var isLoading = false
    private(set) var didLoad = false
    private(set) var failed = false
    private(set) var names: [String: String] = [:]
    private(set) var month: Date
    private(set) var monthSummary = HistoryMath.MonthSummary(workoutCount: 0, trainedDays: [], totalDuration: 0, totalVolumeKg: 0)
    var calendar: Calendar

    @ObservationIgnored private let events: HistoryEvents

    init(context: HistoryContext, events: HistoryEvents, calendar: Calendar = .current, now: Date = Date()) {
        self.context = context
        self.events = events
        self.calendar = calendar
        month = now
    }

    // MARK: Loading

    func load() async {
        names = await context.loadNames()
        await reload(count: Self.pageSize)
    }

    /// Reloads the pages already shown (after an edit elsewhere) and the month.
    func refresh() async {
        await reload(count: max(workouts.count, Self.pageSize))
    }

    private func reload(count: Int) async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            workouts = try await context.workouts.finishedWorkouts(userId: context.userId, before: nil, limit: count)
            hasMore = workouts.count == count
            try await loadMonth()
            failed = false
        } catch {
            failed = true
        }
        didLoad = true
    }

    /// The next page; a no-op while loading or when everything is shown.
    func loadMoreIfNeeded(current: WorkoutSnapshot) async {
        guard hasMore, !isLoading, current.id == workouts.last?.id, let cursor = workouts.last?.startedAt else { return }
        isLoading = true
        defer { isLoading = false }
        guard let next = try? await context.workouts.finishedWorkouts(
            userId: context.userId, before: cursor, limit: Self.pageSize
        ) else { return }
        workouts += next
        hasMore = next.count == Self.pageSize
    }

    // MARK: Calendar

    func shiftMonth(by delta: Int) async {
        guard let shifted = calendar.date(byAdding: .month, value: delta, to: month) else { return }
        month = shifted
        try? await loadMonth()
    }

    var canShowNextMonth: Bool { HistoryMath.monthRange(containing: month, calendar: calendar).upperBound <= Date() }

    private func loadMonth() async throws {
        let range = HistoryMath.monthRange(containing: month, calendar: calendar)
        let inMonth = try await context.workouts.workouts(userId: context.userId, from: range.lowerBound, to: range.upperBound)
        monthSummary = HistoryMath.monthSummary(of: inMonth, month: month, calendar: calendar)
    }

    // MARK: Delete and undo

    func delete(_ workout: WorkoutSnapshot, title: String) async {
        do {
            try await context.editor.delete(workoutId: workout.id)
            events.undo = HistoryEvents.PendingUndo(id: workout.id, title: title)
            events.changed()
            await refresh()
        } catch {
            failed = true
        }
    }

    func undoDelete() async {
        guard let pending = events.undo else { return }
        events.undo = nil
        do {
            try await context.editor.undoDelete(workoutId: pending.id)
            events.changed()
            await refresh()
        } catch {
            failed = true
        }
    }

    // MARK: Display

    func title(of workout: WorkoutSnapshot, fallback: String) -> String { workout.name ?? fallback }

    func exerciseNames(of workout: WorkoutSnapshot) -> String {
        workout.exercises.map { names[HistoryContext.id(of: $0.ref)] ?? "—" }.joined(separator: ", ")
    }

    func volumeText(of workout: WorkoutSnapshot) -> String { context.weightText(WorkoutSummary.volume(of: workout)) }
}

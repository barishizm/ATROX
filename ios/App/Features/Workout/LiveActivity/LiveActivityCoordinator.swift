import DataKit
import Foundation
import Observation

/// Keeps the workout Live Activity in step with the workout and the rest timer (P038).
///
/// Lifecycle: starts with the first sync of an active workout, updates when the exercise, set or rest changes (the
/// clocks themselves are drawn by the system), ends with a summary when the workout is finished and without one
/// when it is cancelled or discarded. On launch, activities left behind by a crash are ended.
@MainActor
final class LiveActivityCoordinator {
    typealias State = WorkoutActivityAttributes.ContentState

    /// How long the summary stays on the Lock Screen after the workout.
    static let summaryDuration: TimeInterval = 2 * 60

    private let session: WorkoutSession
    private let rest: RestTimerController
    private let service: any LiveActivityService
    private let exerciseName: (ExerciseRef) -> String
    private let fallbackName: String
    private let isEnabled: () -> Bool
    private let clock: () -> Date

    private var shownWorkoutId: UUID?
    private var shownState: State?
    private var isSyncing = false
    private var needsAnotherSync = false
    private var isTracking = false

    init(
        session: WorkoutSession, rest: RestTimerController, service: any LiveActivityService,
        fallbackName: String, exerciseName: @escaping (ExerciseRef) -> String,
        isEnabled: @escaping () -> Bool = { true }, clock: @escaping () -> Date = { Date() }
    ) {
        self.session = session
        self.rest = rest
        self.service = service
        self.fallbackName = fallbackName
        self.exerciseName = exerciseName
        self.isEnabled = isEnabled
        self.clock = clock
    }

    /// Cleans up leftovers, shows the current workout (if any) and follows changes from then on.
    func start() async {
        let keep = session.phase == .active ? session.workout?.id : nil
        await service.endAll(except: keep)
        await requestSync()
        guard !isTracking else { return }
        isTracking = true
        track()
    }

    /// The Settings toggle changed.
    func preferenceChanged() async { await requestSync() }

    // MARK: Following changes

    private func track() {
        withObservationTracking {
            _ = session.phase
            _ = session.workout
            _ = rest.run
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.track()
                await self?.requestSync()
            }
        }
    }

    /// One sync at a time; changes that arrive meanwhile trigger one more pass.
    func requestSync() async {
        if isSyncing {
            needsAnotherSync = true
            return
        }
        isSyncing = true
        repeat {
            needsAnotherSync = false
            await sync()
        } while needsAnotherSync
        isSyncing = false
    }

    // MARK: Sync

    private func sync() async {
        let allowed = isEnabled() && service.areActivitiesEnabled
        let now = clock()
        switch session.phase {
        case .active:
            guard let workout = session.workout else { return }
            guard allowed else {
                await endShown(summary: nil)
                return
            }
            let state = WorkoutActivityMapper.state(workout: workout, rest: rest.run, now: now, name: exerciseName)
            guard workout.id != shownWorkoutId || state != shownState else { return }
            if let shownWorkoutId, shownWorkoutId != workout.id { await endShown(summary: nil) }
            await service.upsert(
                WorkoutActivityMapper.attributes(for: workout, fallbackName: fallbackName),
                state: state, staleDate: WorkoutActivityMapper.staleDate(for: state)
            )
            shownWorkoutId = workout.id
            shownState = state
        case .finished(let workout):
            let summary = allowed && shownWorkoutId == workout.id
                ? WorkoutActivityMapper.finalState(
                    of: WorkoutActivityMapper.state(workout: workout, rest: nil, now: now, name: exerciseName),
                    endedAt: workout.endedAt ?? now
                )
                : nil
            await endShown(summary: summary)
        case .idle, .discarded, .cancelled:
            await endShown(summary: nil)
        }
    }

    private func endShown(summary: State?) async {
        guard let id = shownWorkoutId else { return }
        shownWorkoutId = nil
        shownState = nil
        await service.end(workoutId: id, finalState: summary, dismissAfter: Self.summaryDuration)
    }
}

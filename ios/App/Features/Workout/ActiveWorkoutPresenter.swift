import DataKit
import Foundation
import Observation

/// Owns the active-workout screen's model and whether its full-screen cover is open. The cover can be minimized
/// (closed) while the workout keeps running; the mini bar above the tab bar reopens it.
@MainActor
@Observable
final class ActiveWorkoutPresenter {
    private(set) var model: ActiveWorkoutModel?
    var isPresented = false
    /// The summary of the workout that was just finished; shown in place of the workout screen.
    private(set) var summary: WorkoutSummaryModel?

    var hasActiveWorkout: Bool { model?.isActive == true }

    /// Loads the shared session (restoring a workout that survived an app kill). Safe to call repeatedly.
    func prepare(container: AppContainer) async {
        guard model == nil else { return }
        model = await container.makeActiveWorkoutModel()
        await model?.load()
    }

    func resume() { if hasActiveWorkout { isPresented = true } }

    func startEmpty(container: AppContainer) async {
        await prepare(container: container)
        guard let model else { return }
        if !model.isActive { try? await model.session.startEmpty() }
        isPresented = model.isActive
    }

    func start(routineId: UUID, dayId: UUID, container: AppContainer) async {
        await prepare(container: container)
        guard let model else { return }
        if !model.isActive { try? await model.session.start(routineId: routineId, dayId: dayId) }
        isPresented = model.isActive
    }

    /// The workout ended (finished, discarded or cancelled): close the screen.
    func ended() { isPresented = false }

    /// A finish went through: a kept workout is written to Apple Health and shown on the summary screen; a
    /// discarded one just closes the screen.
    func finished(_ result: WorkoutSession.FinishResult, model: ActiveWorkoutModel, container: AppContainer) async {
        guard case .finished(let workout) = result else { return ended() }
        let records = model.summaryRecords(for: workout)
        let names = model.exerciseNames(of: workout)
        model.recordHits = []
        if let recorder = container.workoutHealthRecorder() { Task { await recorder.record(workoutId: workout.id) } }
        summary = await container.makeSummaryModel(
            workout: workout, records: records, names: names, unit: model.unit, decimalSeparator: model.decimalSeparator
        )
        if summary == nil { ended() }
    }

    /// The summary was saved: close the screen.
    func summaryDone() {
        summary = nil
        isPresented = false
    }
}

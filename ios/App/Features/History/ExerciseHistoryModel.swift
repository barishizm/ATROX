import DataKit
import Foundation
import Observation
import StrengthKit

/// All sessions of one exercise (P042): best sets, e1RM over time and the standing records. Also feeds the
/// "Your data" block of the exercise detail screen.
@MainActor
@Observable
final class ExerciseHistoryModel {
    /// Sessions read for the chart and the list; more than a few years of weekly training.
    static let sessionLimit = 400

    let ref: ExerciseRef
    let context: HistoryContext
    private(set) var sessions: [ExerciseSession] = []
    private(set) var progress = HistoryMath.progress(of: [])
    private(set) var marks: [RecordMark] = []
    private(set) var name = ""
    private(set) var isLoading = true
    private(set) var failed = false

    init(ref: ExerciseRef, context: HistoryContext) {
        self.ref = ref
        self.context = context
    }

    func load() async {
        name = await context.loadNames()[HistoryContext.id(of: ref)] ?? ""
        do {
            sessions = try await context.workouts.history(userId: context.userId, ref: ref, limit: Self.sessionLimit)
            progress = HistoryMath.progress(of: sessions)
            marks = try await context.records.current(userId: context.userId, ref: ref)
            failed = false
        } catch {
            failed = true
        }
        isLoading = false
    }

    var isEmpty: Bool { progress.points.isEmpty }

    /// One chart point per session with an estimated 1RM, in the display unit.
    struct ChartPoint: Identifiable, Equatable {
        let date: Date
        let value: Double
        var id: Date { date }
    }

    var chartPoints: [ChartPoint] {
        progress.points.compactMap { point in
            point.e1rmKg.map { ChartPoint(date: point.date, value: context.unit.value(fromKilograms: $0)) }
        }
    }

    var heaviestText: String? {
        progress.heaviest.map { context.setText($0.input) }
    }

    var bestE1rmText: String? { progress.bestE1rmKg.map(context.weightText) }

    /// The standing record of a kind (weight, e1RM or volume), formatted.
    func recordText(_ metric: RecordMetric) -> String? {
        marks.filter { $0.metric == metric }.map(\.value).max().map(context.weightText)
    }

    /// "100 kg × 5, 100 kg × 5" for one session's working sets (warm-ups last-resort only when nothing else).
    func setsText(of session: ExerciseSession) -> String {
        let working = session.sets.filter { $0.input.setType != .warmup }
        return (working.isEmpty ? session.sets : working).map { context.setText($0.input) }.joined(separator: ", ")
    }
}

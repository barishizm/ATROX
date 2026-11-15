import AppIntents
import Foundation

// App Intents (P096): "Start workout", "Log my weight", "Show my Strength Score". They are compiled into the app
// (Shortcuts, Siri, Spotlight; `ATROXShortcuts`) and into the widget extension (the Control Center / Action Button
// control runs `StartWorkoutIntent`).

/// How the app answers a weigh-in that came from Shortcuts or Siri.
enum WeightLogOutcome: Sendable, Equatable {
    case saved
    case signedOut
    case failed
}

/// Bridge from the intents to the running app. The app installs the closures at launch; an intent that needs the
/// app opens it first (`openAppWhenRun`), so the closures are there when `perform` runs. A link posted while no
/// closure is installed waits in the app group (`PendingLinkInbox`) until the app is in front.
@MainActor
final class IntentCommandCenter {
    static let shared = IntentCommandCenter()

    var openLink: (@MainActor (URL) -> Void)?
    var logWeight: (@MainActor (Double) async -> WeightLogOutcome)?

    /// Hands a link to the app: straight to the router when the app is running, through the inbox otherwise.
    func deliver(_ url: URL, inbox: PendingLinkInbox? = .appGroup()) {
        if let openLink {
            openLink(url)
        } else {
            inbox?.post(url)
        }
    }
}

/// A link that an intent could not hand to a running app; the app drains it when it becomes active.
struct PendingLinkInbox: @unchecked Sendable {
    static let key = "widget.pendingLink.v1"
    /// An old tap is not replayed: a link that waited longer than this is dropped.
    static let maxAge: TimeInterval = 120

    private let defaults: UserDefaults

    init(defaults: UserDefaults) { self.defaults = defaults }

    static func appGroup(id: String? = Bundle.main.infoDictionary?["AppGroupID"] as? String) -> PendingLinkInbox? {
        guard let id, !id.isEmpty, !id.hasPrefix("$("), let defaults = UserDefaults(suiteName: id) else { return nil }
        return PendingLinkInbox(defaults: defaults)
    }

    func post(_ url: URL, at date: Date = .now) {
        defaults.set(["url": url.absoluteString, "at": date.timeIntervalSince1970], forKey: Self.key)
    }

    /// Takes the waiting link, leaving none behind; nil when empty or too old.
    func take(now: Date = .now) -> URL? {
        defer { defaults.removeObject(forKey: Self.key) }
        guard let stored = defaults.dictionary(forKey: Self.key),
              let string = stored["url"] as? String, let at = stored["at"] as? Double,
              now.timeIntervalSince1970 - at <= Self.maxAge else { return nil }
        return URL(string: string)
    }
}

// MARK: Program day entity

/// One day of the user's active program, offered as the parameter of "Start workout".
struct WorkoutDayEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "intent.day.type"
    static let defaultQuery = WorkoutDayQuery()

    var id: UUID
    var dayName: String
    var routineName: String

    init(_ day: WidgetSnapshot.PlannedDay) {
        id = day.dayId
        dayName = day.dayName
        routineName = day.routineName
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: LocalizedStringResource(stringLiteral: dayName),
            subtitle: LocalizedStringResource(stringLiteral: routineName)
        )
    }
}

struct WorkoutDayQuery: EntityQuery {
    func entities(for identifiers: [UUID]) async throws -> [WorkoutDayEntity] {
        guard let snapshot = WidgetSnapshotStore.appGroup()?.read() else { return [] }
        return identifiers.compactMap { snapshot.day(id: $0) }.map(WorkoutDayEntity.init)
    }

    func suggestedEntities() async throws -> [WorkoutDayEntity] {
        (WidgetSnapshotStore.appGroup()?.read()?.days ?? []).map(WorkoutDayEntity.init)
    }
}

// MARK: Intents

/// Starts the chosen program day, or the next planned one when no day is given.
struct StartWorkoutIntent: AppIntent {
    static let title: LocalizedStringResource = "intent.start.title"
    static let description = IntentDescription("intent.start.description")
    static let openAppWhenRun = true

    @Parameter(title: "intent.start.day")
    var day: WorkoutDayEntity?

    init() {}

    init(day: WorkoutDayEntity?) { self.day = day }

    /// The link the app opens: the chosen day, else the next planned one, else just the Workout tab.
    static func link(day: UUID?, snapshot: WidgetSnapshot?) -> URL {
        let target = day.flatMap { snapshot?.day(id: $0) } ?? snapshot?.next
        return target.map { WidgetLink.startWorkout($0) } ?? WidgetLink.tab("workout")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        let snapshot = WidgetSnapshotStore.appGroup()?.read()
        IntentCommandCenter.shared.deliver(Self.link(day: day?.id, snapshot: snapshot))
        return .result()
    }
}

/// Saves a weigh-in (the same record as the Profile tab's "Log weight").
struct LogWeightIntent: AppIntent {
    static let title: LocalizedStringResource = "intent.weight.title"
    static let description = IntentDescription("intent.weight.description")
    static let openAppWhenRun = false

    @Parameter(title: "intent.weight.value", requestValueDialog: "intent.weight.ask")
    var weight: Measurement<UnitMass>

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let kilograms = weight.converted(to: .kilograms).value
        guard let value = WeightEntry.kilograms(kilograms) else {
            return .result(dialog: IntentDialog(LocalizedStringResource("intent.weight.invalid")))
        }
        let outcome = await IntentCommandCenter.shared.logWeight?(value) ?? .failed
        switch outcome {
        case .saved:
            let text = Measurement(value: value, unit: UnitMass.kilograms).formatted(.measurement(width: .abbreviated))
            return .result(dialog: IntentDialog(LocalizedStringResource("intent.weight.saved \(text)")))
        case .signedOut:
            return .result(dialog: IntentDialog(LocalizedStringResource("intent.signedout")))
        case .failed:
            return .result(dialog: IntentDialog(LocalizedStringResource("intent.weight.failed")))
        }
    }
}

/// Says the current overall Strength Score.
struct ShowScoreIntent: AppIntent {
    static let title: LocalizedStringResource = "intent.score.title"
    static let description = IntentDescription("intent.score.description")
    static let openAppWhenRun = false

    /// What the dialog says for a snapshot.
    static func dialog(for snapshot: WidgetSnapshot?) -> LocalizedStringResource {
        switch WidgetContentState(snapshot) {
        case .signedOut: return "intent.signedout"
        case .noScore: return "intent.score.none"
        case .ready:
            guard let score = snapshot?.score else { return "intent.score.none" }
            return score.isProvisional
                ? LocalizedStringResource("intent.score.provisional \(score.value)")
                : LocalizedStringResource("intent.score.value \(score.value)")
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: IntentDialog(Self.dialog(for: WidgetSnapshotStore.appGroup()?.read())))
    }
}

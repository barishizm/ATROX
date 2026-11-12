import Foundation
import Observation

/// Which routine is active and which routine day falls on which weekday (P033). Kept on the device in
/// `UserDefaults`, per user; moving it into the synced model is listed under "Ertelenenler" in docs/ILERLEME.md.
@MainActor
@Observable
public final class RoutinePlanStore {
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let activeKey: String
    @ObservationIgnored private let weekKey: String

    public private(set) var activeRoutineId: UUID?
    /// `Calendar` weekday numbers (1 = Sunday … 7 = Saturday) → routine day.
    public private(set) var dayByWeekday: [Int: UUID]

    public init(userId: UUID, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        activeKey = "routine.active.v1.\(userId.uuidString)"
        weekKey = "routine.week.v1.\(userId.uuidString)"
        activeRoutineId = defaults.string(forKey: activeKey).flatMap(UUID.init(uuidString:))
        let stored = defaults.dictionary(forKey: weekKey) as? [String: String] ?? [:]
        var map: [Int: UUID] = [:]
        for (key, value) in stored {
            if let weekday = Int(key), (1...7).contains(weekday), let id = UUID(uuidString: value) { map[weekday] = id }
        }
        dayByWeekday = map
    }

    public func setActive(_ id: UUID?) {
        activeRoutineId = id
        defaults.set(id?.uuidString, forKey: activeKey)
    }

    /// Puts `dayId` on `weekday`, or frees the weekday with `nil`.
    public func assign(dayId: UUID?, toWeekday weekday: Int) {
        guard (1...7).contains(weekday) else { return }
        dayByWeekday[weekday] = dayId
        persistWeek()
    }

    public func weekdays(of dayId: UUID) -> [Int] {
        dayByWeekday.filter { $0.value == dayId }.keys.sorted()
    }

    /// Drops assignments to days that no longer exist (deleted day or routine) and an active routine that is gone.
    public func prune(validDayIds: Set<UUID>, validRoutineIds: Set<UUID>) {
        let kept = dayByWeekday.filter { validDayIds.contains($0.value) }
        if kept.count != dayByWeekday.count {
            dayByWeekday = kept
            persistWeek()
        }
        if let active = activeRoutineId, !validRoutineIds.contains(active) { setActive(nil) }
    }

    private func persistWeek() {
        defaults.set(Dictionary(uniqueKeysWithValues: dayByWeekday.map { (String($0.key), $0.value.uuidString) }), forKey: weekKey)
    }
}

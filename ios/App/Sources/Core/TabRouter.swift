import Observation

/// Navigation path of one tab, typed by that tab's `Route` enum.
@MainActor
@Observable
final class TabRouter<Route: Hashable> {
    var path: [Route] = []

    func push(_ route: Route) { path.append(route) }
    func pop() { _ = path.popLast() }
    func popToRoot() { path.removeAll() }
}

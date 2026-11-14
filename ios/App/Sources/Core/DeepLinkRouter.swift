import DataKit
import Foundation
import Observation

/// Every way into the app that is not a tap on a tab (P088): universal links, the `atrox://` scheme, notification
/// taps, widgets and the Live Activity all resolve to one of these.
enum DeepLink: Equatable, Sendable {
    /// `/u/<username>`: open that person's friend-request screen.
    case friendInvite(username: String)
    case tab(AppTab)
    case weeklySummary

    /// Where universal links live (`APP_LINK_HOST` in the xcconfig files) and the app's own scheme.
    struct Configuration: Equatable, Sendable {
        var host: String?
        var scheme: String

        init(host: String?, scheme: String) {
            let trimmed = host?.trimmingCharacters(in: .whitespaces).lowercased()
            self.host = (trimmed?.isEmpty == false && trimmed?.hasPrefix("$(") == false) ? trimmed : nil
            self.scheme = scheme.lowercased()
        }

        init(infoDictionary: [String: Any]) {
            self.init(host: infoDictionary["AppLinkHost"] as? String, scheme: infoDictionary["AppURLScheme"] as? String ?? "atrox")
        }

        static var current: Configuration { Configuration(infoDictionary: Bundle.main.infoDictionary ?? [:]) }
    }

    /// nil for anything that is not a navigation link (auth callbacks, Google's reversed scheme, foreign hosts).
    init?(url: URL, configuration: Configuration = .current) {
        guard let scheme = url.scheme?.lowercased() else { return nil }
        let parts: [String]
        switch scheme {
        case "https":
            guard let host = url.host?.lowercased(), let expected = configuration.host, host == expected else { return nil }
            parts = url.pathComponents.filter { $0 != "/" }
        case configuration.scheme:
            // atrox://u/alice, atrox://today
            parts = ([url.host].compactMap { $0 } + url.pathComponents.filter { $0 != "/" })
        default:
            return nil
        }
        guard let first = parts.first?.lowercased() else { return nil }
        switch first {
        case "u":
            guard parts.count == 2 else { return nil }
            let name = SocialTextPolicy.canonical(parts[1])
            guard SocialTextPolicy.usernameIssue(name) == nil else { return nil }
            self = .friendInvite(username: name)
        case "today": self = .tab(.today)
        case "workout": self = .tab(.workout)
        case "analysis": self = .tab(.analysis)
        case "coach": self = .tab(.coach)
        case "profile": self = .tab(.profile)
        case "weekly": self = .weeklySummary
        default: return nil
        }
    }

    /// The `atrox://` form, for widgets and Live Activities (`widgetURL`).
    func url(scheme: String = Configuration.current.scheme) -> URL? {
        switch self {
        case .friendInvite(let name): URL(string: "\(scheme)://u/\(name)")
        case .tab(let tab): URL(string: "\(scheme)://\(tab.rawValue)")
        case .weeklySummary: URL(string: "\(scheme)://weekly")
        }
    }

    /// The shareable web link (`https://<host>/u/<name>`); nil until a link host is configured.
    static func inviteLink(username: String, configuration: Configuration = .current) -> URL? {
        guard let host = configuration.host else { return nil }
        return URL(string: "https://\(host)/u/\(SocialTextPolicy.canonical(username))")
    }
}

/// Holds the link that has not been opened yet. A link that arrives while signed out or during onboarding stays here;
/// the main shell opens it as soon as it appears.
@MainActor
@Observable
final class DeepLinkRouter {
    private(set) var pending: DeepLink?

    func receive(_ link: DeepLink) { pending = link }

    /// Handles a URL if it is a navigation link; false means someone else (auth, Google) should look at it.
    @discardableResult
    func receive(url: URL, configuration: DeepLink.Configuration = .current) -> Bool {
        guard let link = DeepLink(url: url, configuration: configuration) else { return false }
        pending = link
        return true
    }

    /// Takes the pending link, leaving none behind.
    func consume() -> DeepLink? {
        defer { pending = nil }
        return pending
    }
}

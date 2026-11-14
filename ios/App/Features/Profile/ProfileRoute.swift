enum ProfileRoute: Hashable, Sendable {
    case social
    case invite(username: String)
    case paywall
    case editProfile
    case measurements
    case settings
    case consentHistory
    case deleteAccount
    case about
    case licenses
    case howItWorks
}

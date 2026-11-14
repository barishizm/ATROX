import DesignSystem
import SwiftUI

/// The Profile tab: loads the model for the signed-in user, then hosts the tab's navigation stack.
struct ProfileTabView: View {
    @Environment(AppContainer.self) private var container
    @Bindable var router: TabRouter<ProfileRoute>
    @State private var model: ProfileModel?
    @State private var account: AccountModel?
    @State private var failed = false

    var body: some View {
        NavigationStack(path: $router.path) {
            content
                .navigationTitle("shell.tabbar.profile")
                .navigationDestination(for: ProfileRoute.self) { route in
                    if let model, let account { destination(route, model: model, account: account) }
                }
        }
        .task { await prepare() }
    }

    @ViewBuilder private var content: some View {
        if let model {
            switch model.loadState {
            case .loading: LoadingState()
            case .failed: ErrorState(message: "profile.error.load") { Task { await model.load() } }
            case .loaded: ProfileRootView(model: model)
            }
        } else if failed {
            ErrorState(message: "profile.error.unavailable") { Task { await prepare() } }
        } else {
            LoadingState()
        }
    }

    @ViewBuilder
    private func destination(_ route: ProfileRoute, model: ProfileModel, account: AccountModel) -> some View {
        switch route {
        case .social: SocialRootView()
        case .invite(let username): SocialInviteView(username: username)
        case .paywall: PaywallPlaceholderView()
        case .editProfile: ProfileEditView(model: model)
        case .measurements: MeasurementsView(model: model)
        case .settings: SettingsView(model: model, account: account)
        case .consentHistory: ConsentHistoryView(model: model)
        case .deleteAccount: DeleteAccountView(account: account)
        case .about: AboutView()
        case .licenses: LicensesView()
        case .howItWorks: HowItWorksView()
        }
    }

    private func prepare() async {
        guard model == nil else { return }
        guard let created = await container.makeProfileModel() else {
            failed = true
            return
        }
        failed = false
        account = container.makeAccountModel(userId: created.userId)
        model = created
        await created.load()
    }
}

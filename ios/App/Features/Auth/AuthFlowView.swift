import DesignSystem
import SwiftUI

/// Signed-out flow: mascot welcome → methods (sign up | sign in) → e-mail form → verification / password reset.
struct AuthFlowView: View {
    @Bindable var model: AuthFlowModel

    var body: some View {
        NavigationStack(path: $model.path) {
            root
                .navigationDestination(for: AuthRoute.self) { route in
                    switch route {
                    case .quiz: PlanQuizView(authModel: model)
                    case .methods(let mode): AuthMethodsView(model: model, mode: mode)
                    case .signUp: EmailSignUpView(model: model)
                    case .signIn(let email): EmailSignInView(model: model, email: email)
                    case .verify(let email): VerificationPendingView(model: model, email: email)
                    case .reset(let email): PasswordResetView(model: model, email: email)
                    }
                }
        }
        .tint(DSColor.accent)
    }

    /// UI tests start on the sign-up methods (no mascot intro) unless they ask for the intro.
    @ViewBuilder private var root: some View {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-uitest-fake-auth"), !args.contains("-uitest-auth-intro") {
            AuthMethodsView(model: model, mode: .signUp, isRoot: true)
        } else {
            WelcomeView(model: model)
        }
    }
}

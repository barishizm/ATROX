import DesignSystem
import SwiftUI

/// Signed-out flow: welcome → (sign up | sign in) → verification / password reset.
struct AuthFlowView: View {
    @Bindable var model: AuthFlowModel

    var body: some View {
        NavigationStack(path: $model.path) {
            WelcomeView(model: model)
                .navigationDestination(for: AuthRoute.self) { route in
                    switch route {
                    case .signUp: EmailSignUpView(model: model)
                    case .signIn(let email): EmailSignInView(model: model, email: email)
                    case .verify(let email): VerificationPendingView(model: model, email: email)
                    case .reset(let email): PasswordResetView(model: model, email: email)
                    }
                }
        }
        .tint(DSColor.accent)
    }
}

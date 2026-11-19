import DesignSystem
import SwiftUI

/// First screen: a full-bleed, swipeable three-page product intro (workouts, meals, analysis).
/// The bottom of each image melts into a dark glass blur that carries a two-line caption. Tapping anywhere
/// (or swiping) moves on, "Skip" jumps to the last page, and the last page's "Get started" opens the
/// register / log-in screen.
struct WelcomeView: View {
    let model: AuthFlowModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var page = 0

    private struct IntroPage: Identifiable {
        let image: String
        let caption: LocalizedStringKey
        /// Which part of the photo survives the side crop on tall screens (keeps the mascot in view).
        var focus: Alignment = .center
        /// A UI graphic rather than a photo: shown whole (never cropped) on this backdrop colour.
        var fitBackdrop: Color?
        var id: String { image }
    }

    private static let pages = [
        IntroPage(image: "IntroTracking", caption: "auth.intro.page.tracking", focus: .trailing),
        IntroPage(image: "IntroNutrition", caption: "auth.intro.page.nutrition"),
        IntroPage(image: "IntroAnalysis", caption: "auth.intro.page.analysis", fitBackdrop: Color(red: 21 / 255, green: 28 / 255, blue: 36 / 255))
    ]

    private var isLast: Bool { page == Self.pages.count - 1 }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                ZStack {
                    ForEach(Array(Self.pages.enumerated()), id: \.element.id) { index, item in
                        (item.fitBackdrop ?? .black)
                            .overlay(alignment: item.fitBackdrop == nil ? item.focus : .top) {
                                if item.fitBackdrop == nil {
                                    Image(item.image).resizable().scaledToFill()
                                } else {
                                    Image(item.image).resizable().scaledToFit()
                                }
                            }
                            .clipped()
                            .opacity(index == page ? 1 : 0)
                            .accessibilityHidden(true)
                    }
                }
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { advance() }
                .gesture(
                    DragGesture(minimumDistance: 24).onEnded { value in
                        if value.translation.width < -40 {
                            advance()
                        } else if value.translation.width > 40 {
                            jump(to: max(page - 1, 0))
                        }
                    }
                )

                VStack(spacing: 0) {
                    HStack {
                        Spacer()
                        if !isLast {
                            Button("auth.intro.skip") { jump(to: Self.pages.count - 1) }
                                .buttonStyle(.glass)
                                .foregroundStyle(.white)
                                .accessibilityIdentifier("welcome-skip")
                                .transition(.opacity)
                        }
                    }
                    .padding(.horizontal, Spacing.lg)
                    .padding(.top, Spacing.sm)
                    Spacer()
                    bottomPanel(height: proxy.size.height)
                }
            }
        }
        .background(Color.black)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { model.clearError() }
        .accessibilityIdentifier("auth-welcome")
    }

    /// Dark progressive blur from the lower half of the screen down, with caption, dots and the action on top.
    private func bottomPanel(height: CGFloat) -> some View {
        VStack(spacing: Spacing.md) {
            Text(Self.pages[page].caption)
                .font(Font.system(.title3, weight: .semibold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
                .id(page)
                .transition(.opacity)
            pageDots
            action
            #if DEBUG
            AuthDebugTools().environment(\.colorScheme, .dark)
            #endif
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.top, 72)
        .padding(.bottom, Spacing.lg)
        .frame(maxWidth: .infinity)
        .background(alignment: .bottom) {
            ZStack {
                Rectangle().fill(.regularMaterial)
                LinearGradient(colors: [.black.opacity(0.15), .black.opacity(0.9)], startPoint: .top, endPoint: .bottom)
            }
            .environment(\.colorScheme, .dark)
            .mask(
                LinearGradient(
                    stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.5)],
                    startPoint: .top, endPoint: .bottom
                )
            )
            .ignoresSafeArea(edges: .bottom)
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: page)
    }

    private var pageDots: some View {
        HStack(spacing: Spacing.xs) {
            ForEach(0..<Self.pages.count, id: \.self) { index in
                Capsule()
                    .fill(index == page ? Color.white : Color.white.opacity(0.35))
                    .frame(width: index == page ? 20 : 8, height: 8)
            }
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder private var action: some View {
        if isLast {
            Button { model.path.append(.account(.signUp)) } label: {
                Text("auth.intro.getStarted")
                    .font(DSFont.headline)
                    .frame(maxWidth: .infinity, minHeight: HitTarget.button - 16)
            }
            .buttonStyle(.glassProminent)
            .tint(DSColor.accentFill)
            .accessibilityIdentifier("welcome-continue")
        } else {
            Button { advance() } label: {
                Text("auth.intro.tapToNext")
                    .font(DSFont.callout.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(maxWidth: .infinity, minHeight: HitTarget.button - 16)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("welcome-next")
        }
    }

    private func advance() { jump(to: min(page + 1, Self.pages.count - 1)) }

    private func jump(to target: Int) {
        guard target != page else { return }
        if reduceMotion { page = target } else { withAnimation(.easeInOut(duration: 0.3)) { page = target } }
    }
}

/// How to get in: Apple first (per Apple's guidelines), then Google, then e-mail. Same screen for
/// sign-up and sign-in; only the mascot's line and the e-mail destination differ.
struct AuthMethodsView: View {
    let model: AuthFlowModel
    let mode: AuthMode
    /// Shown as the first screen (no intro in front of it): offer a way over to sign-in.
    var isRoot = false
    var legal: LegalLinks = .current

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.xl) {
                MascotSpeech(
                    image: mode == .signUp ? "MascotExcited" : "MascotCool",
                    message: mode == .signUp ? "auth.methods.signUp" : "auth.methods.signIn",
                    mascotWidth: 160
                )
                actions
                LegalLinksView(links: legal)
                #if DEBUG
                if isRoot { AuthDebugTools() }
                #endif
            }
            .padding(Spacing.lg)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(DSColor.background)
        .toolbar(isRoot ? .hidden : .automatic, for: .navigationBar)
        .onAppear { model.clearError() }
        .accessibilityIdentifier(mode == .signUp ? "auth-methods-signup" : "auth-methods-signin")
    }

    private var actions: some View {
        VStack(spacing: Spacing.md) {
            AppleSignInButton { Task { await model.signInWithApple() } }
                .frame(height: HitTarget.button)
                .disabled(model.isBusy)
                .overlay { if model.busy == .apple { ProgressView().tint(.gray) } }
                .accessibilityIdentifier("welcome-apple")
            SecondaryButton("auth.welcome.google", icon: Image("GoogleLogo"), isLoading: model.busy == .google) {
                Task { await model.signInWithGoogle() }
            }
            .disabled(model.isBusy)
            .accessibilityIdentifier("welcome-google")
            SecondaryButton(mode == .signUp ? "auth.welcome.email" : "auth.methods.emailSignIn", systemImage: "envelope.fill") {
                model.path.append(mode == .signUp ? .signUp : .signIn(email: ""))
            }
            .disabled(model.isBusy)
            .accessibilityIdentifier("welcome-email")
            if let error = model.error { AuthErrorBanner(error: error) }
            if mode == .signUp {
                // Sign-up is the last step of the questions; people who already have an account must not have to
                // backtrack through them, so the way over to sign-in is offered right here.
                VStack(spacing: Spacing.xs) {
                    Text("auth.methods.haveAccount").foregroundStyle(DSColor.textSecondary)
                    Button("auth.welcome.signIn") {
                        model.path.append(isRoot ? .signIn(email: "") : .methods(.signIn))
                    }
                    .fontWeight(.semibold)
                    .disabled(model.isBusy)
                    .accessibilityIdentifier("welcome-signin")
                }
                .font(DSFont.callout)
                .frame(minHeight: HitTarget.minimum)
            }
        }
    }
}

#if DEBUG
/// Developer shortcuts (compiled out of Staging/Release): skip auth, open the debug menu.
private struct AuthDebugTools: View {
    @Environment(AppContainer.self) private var container
    @State private var showDebugMenu = false

    var body: some View {
        VStack(spacing: Spacing.xs) {
            Button("auth.signin.debugContinue") { container.debugSignIn() }
                .accessibilityIdentifier("auth-debug-continue")
            Button("debug.menu.open") { showDebugMenu = true }
                .accessibilityIdentifier("auth-debug-menu")
        }
        .font(DSFont.caption)
        .sheet(isPresented: $showDebugMenu) { DebugMenuView() }
    }
}
#endif

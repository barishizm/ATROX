import SwiftUI

/// Centered icon + title + message + optional action; shared by empty / error states.
private struct StateLayout: View {
    let systemImage: String
    let tint: Color
    let title: LocalizedStringKey
    let message: LocalizedStringKey?
    let actionTitle: LocalizedStringKey?
    let action: (@MainActor () -> Void)?

    var body: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: systemImage)
                .font(.system(.largeTitle, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 72, height: 72)
                .background(tint.opacity(0.14), in: Circle())
                .accessibilityHidden(true)
            VStack(spacing: Spacing.xs) {
                Text(title)
                    .font(DSFont.headline)
                    .foregroundStyle(DSColor.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                if let message {
                    Text(message).font(DSFont.callout).foregroundStyle(DSColor.textSecondary)
                }
            }
            .multilineTextAlignment(.center)
            if let actionTitle, let action {
                PrimaryButton(actionTitle, action: action).frame(maxWidth: 280)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(Spacing.lg)
    }
}

/// Nothing to show yet (no workouts, no history…).
public struct EmptyState: View {
    private let systemImage: String
    private let title: LocalizedStringKey
    private let message: LocalizedStringKey?
    private let actionTitle: LocalizedStringKey?
    private let action: (@MainActor () -> Void)?

    public init(
        systemImage: String,
        title: LocalizedStringKey,
        message: LocalizedStringKey? = nil,
        actionTitle: LocalizedStringKey? = nil,
        action: (@MainActor () -> Void)? = nil
    ) {
        self.systemImage = systemImage
        self.title = title
        self.message = message
        self.actionTitle = actionTitle
        self.action = action
    }

    public var body: some View {
        StateLayout(
            systemImage: systemImage, tint: DSColor.accent, title: title,
            message: message, actionTitle: actionTitle, action: action
        )
    }
}

/// Content is loading.
public struct LoadingState: View {
    private let message: LocalizedStringKey?

    /// `nil` message shows the default localized "Loading…".
    public init(_ message: LocalizedStringKey? = nil) { self.message = message }

    public var body: some View {
        VStack(spacing: Spacing.md) {
            ProgressView().controlSize(.large).tint(DSColor.accent)
            Group {
                if let message { Text(message) } else { Text("ds.state.loading", bundle: .module) }
            }
            .font(DSFont.callout)
            .foregroundStyle(DSColor.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(Spacing.xl)
        .accessibilityElement(children: .combine)
    }
}

/// Something failed; offers a retry.
public struct ErrorState: View {
    private let title: LocalizedStringKey?
    private let message: LocalizedStringKey
    private let retry: (@MainActor () -> Void)?

    public init(title: LocalizedStringKey? = nil, message: LocalizedStringKey, retry: (@MainActor () -> Void)? = nil) {
        self.title = title
        self.message = message
        self.retry = retry
    }

    public var body: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(.largeTitle, weight: .semibold))
                .foregroundStyle(DSColor.error)
                .frame(width: 72, height: 72)
                .background(DSColor.error.opacity(0.14), in: Circle())
                .accessibilityHidden(true)
            VStack(spacing: Spacing.xs) {
                Group {
                    if let title { Text(title) } else { Text("ds.errorState.title", bundle: .module) }
                }
                .font(DSFont.headline)
                .foregroundStyle(DSColor.textPrimary)
                .accessibilityAddTraits(.isHeader)
                Text(message).font(DSFont.callout).foregroundStyle(DSColor.textSecondary)
            }
            .multilineTextAlignment(.center)
            if let retry {
                SecondaryButton(title: Text("ds.errorState.retry", bundle: .module), systemImage: "arrow.clockwise", action: retry)
                    .frame(maxWidth: 280)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(Spacing.lg)
        .onAppear { Haptics.play(.error) }
    }
}

#Preview("Dark") { StatesDemo().dsPreview(.dark) }
#Preview("Light") { StatesDemo().dsPreview(.light) }
#Preview("Large type") { StatesDemo().dsPreview(.dark, type: .accessibility3) }

private struct StatesDemo: View {
    var body: some View {
        VStack(spacing: Spacing.lg) {
            EmptyState(
                systemImage: "dumbbell.fill", title: "Henüz antrenman yok",
                message: "İlk antrenmanını kaydet, Güç Skorun hesaplansın.",
                actionTitle: "Antrenman Başlat"
            ) {}
            LoadingState()
            ErrorState(message: "Bağlantı kurulamadı. İnternetini kontrol et.") {}
        }
    }
}

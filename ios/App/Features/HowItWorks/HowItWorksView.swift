import DesignSystem
import SwiftUI

/// "How is it calculated?" (P071): the scoring model in plain language. Reached from Profile › About and from every
/// score screen; the texts are legal-review material (docs/YAYIN-KONTROL.md).
struct HowItWorksView: View {
    @Environment(AppContainer.self) private var container
    @State private var model: HowItWorksModel?

    private struct Step: Identifiable {
        let number: Int
        let icon: String
        var id: Int { number }
    }

    private static let steps = [
        Step(number: 1, icon: "dumbbell"), Step(number: 2, icon: "bolt.heart"), Step(number: 3, icon: "person.3"),
        Step(number: 4, icon: "slider.horizontal.3"), Step(number: 5, icon: "square.stack.3d.up"),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                intro
                stepsSection
                groupsSection
                confidenceSection
                limitsSection
                sourcesSection
                modelSection
                disclaimer
            }
            .padding(Spacing.md)
        }
        .background(DSColor.background)
        .navigationTitle("how.title")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if model == nil { model = HowItWorksModel(container: container) }
            await model?.load()
        }
        .accessibilityIdentifier("how-it-works-screen")
    }

    private var intro: some View {
        Text("how.intro").font(DSFont.body).foregroundStyle(DSColor.textSecondary)
    }

    private func section<Content: View>(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(title).font(DSFont.title).foregroundStyle(DSColor.textPrimary).accessibilityAddTraits(.isHeader)
            content()
        }
    }

    private func text(_ key: LocalizedStringKey) -> some View {
        Text(key).font(DSFont.body).foregroundStyle(DSColor.textSecondary).fixedSize(horizontal: false, vertical: true)
    }

    private var stepsSection: some View {
        section("how.steps.title") {
            VStack(spacing: Spacing.sm) {
                ForEach(Self.steps) { step in
                    Card {
                        HStack(alignment: .top, spacing: Spacing.md) {
                            ZStack {
                                Circle().fill(DSColor.accent.opacity(0.15)).frame(width: 44, height: 44)
                                Image(systemName: step.icon).foregroundStyle(DSColor.accent)
                            }
                            .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: Spacing.xs) {
                                Text(LocalizedStringKey.dynamic("how.step\(step.number).title")).font(DSFont.headline).foregroundStyle(DSColor.textPrimary)
                                text(LocalizedStringKey.dynamic("how.step\(step.number).body"))
                            }
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("how-step-\(step.number)")
                }
            }
        }
    }

    private var groupsSection: some View {
        section("how.groups.title") {
            text("how.groups.intro")
            ForEach(["competitor", "gym", "general"], id: \.self) { group in
                Card {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text(LocalizedStringKey.dynamic("how.group.\(group).title")).font(DSFont.headline).foregroundStyle(DSColor.textPrimary)
                        text(LocalizedStringKey.dynamic("how.group.\(group).body"))
                    }
                }
                .accessibilityElement(children: .combine)
            }
            text("how.groups.reliable")
        }
    }

    private var confidenceSection: some View {
        section("how.confidence.title") {
            text("how.confidence.intro")
            ForEach(["high", "medium", "low"], id: \.self) { level in
                Card {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text(LocalizedStringKey.dynamic("scorescreen.confidence.\(level)")).font(DSFont.headline).foregroundStyle(DSColor.textPrimary)
                        text(LocalizedStringKey.dynamic("how.confidence.\(level)"))
                    }
                }
                .accessibilityElement(children: .combine)
            }
            text("how.confidence.uncertain")
        }
    }

    private var limitsSection: some View {
        section("how.limits.title") {
            ForEach(1...5, id: \.self) { index in
                Label {
                    text(LocalizedStringKey.dynamic("how.limit\(index)"))
                } icon: {
                    Image(systemName: "exclamationmark.circle").foregroundStyle(DSColor.accent)
                }
            }
        }
    }

    private var sourcesSection: some View {
        section("how.sources.title") {
            text("how.sources.intro")
            ForEach(SourceCredit.all) { credit in
                Link(destination: credit.url) {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text(verbatim: credit.name).font(DSFont.headline).foregroundStyle(DSColor.accent)
                        text(LocalizedStringKey.dynamic(credit.noteKey))
                    }
                }
            }
        }
    }

    private var modelSection: some View {
        section("how.model.title") {
            Card {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    if let info = model?.info {
                        LabeledContent("how.model.version") { Text(verbatim: info.version).font(DSFont.numericSmall) }
                            .accessibilityIdentifier("how-model-version")
                        LabeledContent("how.model.source") {
                            Text(info.isDownloaded ? "how.model.source.downloaded" : "how.model.source.embedded")
                        }
                        LabeledContent("how.model.checked") {
                            if let checked = info.lastCheckedAt {
                                Text(checked, format: .dateTime.day().month(.abbreviated).year().hour().minute())
                            } else {
                                Text("how.model.checked.never")
                            }
                        }
                    } else if model?.isLoaded == true {
                        Text("how.model.unavailable").foregroundStyle(DSColor.textSecondary)
                    }
                    if let model, model.canCheck { updateControls(model) }
                }
                .font(DSFont.callout)
            }
        }
    }

    @ViewBuilder
    private func updateControls(_ model: HowItWorksModel) -> some View {
        Button { Task { await model.checkForUpdate() } } label: {
            Text("how.model.check").frame(maxWidth: .infinity, minHeight: HitTarget.minimum - Spacing.sm)
        }
        .buttonStyle(.bordered)
        .disabled(model.update == .checking)
        .accessibilityIdentifier("how-model-check")
        switch model.update {
        case .idle: EmptyView()
        case .checking: ProgressView()
        case .upToDate: Text("how.model.uptodate").foregroundStyle(DSColor.textSecondary)
        case .updated(let version): Text("how.model.updated \(version)").foregroundStyle(DSColor.success)
        case .failed: Text("how.model.failed").foregroundStyle(DSColor.textSecondary)
        }
    }

    private var disclaimer: some View {
        Card {
            Label {
                text("how.disclaimer")
            } icon: {
                Image(systemName: "cross.case").foregroundStyle(DSColor.accent)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("how-disclaimer")
    }
}

/// Datasets and works the scoring and the app draw on (kept in step with the About › Licenses list).
struct SourceCredit: Identifiable, Equatable {
    let name: String
    let noteKey: String
    let url: URL
    var id: String { name }

    static let all: [SourceCredit] = [
        SourceCredit(name: "OpenPowerlifting", noteKey: "how.source.opl", url: URL(string: "https://www.openpowerlifting.org")!),
        SourceCredit(name: "free-exercise-db", noteKey: "how.source.fedb", url: URL(string: "https://github.com/yuhonas/free-exercise-db")!),
        SourceCredit(
            name: "react-native-body-highlighter", noteKey: "how.source.muscle",
            url: URL(string: "https://github.com/HichamELBSI/react-native-body-highlighter")!),
    ]
}

/// Sheet wrapper so a score screen can open the explanation from any navigation stack.
struct HowItWorksSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            HowItWorksView()
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) { Button("how.done") { dismiss() } }
                }
        }
    }
}

private struct HowItWorksButton: ViewModifier {
    @State private var isShown = false

    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { isShown = true } label: { Image(systemName: "info.circle") }
                        .accessibilityLabel(Text("how.open"))
                        .accessibilityIdentifier("how-it-works-button")
                }
            }
            .sheet(isPresented: $isShown) { HowItWorksSheet() }
    }
}

extension View {
    /// An info button that opens "How is it calculated?" in a sheet (score screens).
    func howItWorksButton() -> some View { modifier(HowItWorksButton()) }
}

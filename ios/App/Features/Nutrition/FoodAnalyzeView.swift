import CoachKit
import DataKit
import DesignSystem
import SwiftUI

/// Photo or description → estimate → edit → save. Also the editor for a scanned or searched product.
struct FoodAnalyzeView: View {
    @Bindable var model: FoodAnalyzeModel
    let onSave: (FoodEntryInput) async -> Bool
    let onClose: () -> Void

    @State private var saving = false
    @State private var saveFailed = false
    @State private var showsPaywall = false

    var body: some View {
        NavigationStack {
            Group {
                switch model.phase {
                case .input: describeInput
                case .analyzing: analyzing
                case .result: editor
                case .failed(let error): failure(error)
                }
            }
            .background(DSColor.background.ignoresSafeArea())
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("common.cancel", action: onClose) }
            }
            .task { await model.startIfNeeded() }
            .sheet(isPresented: $showsPaywall) { NavigationStack { PaywallView(feature: .foodAnalysisUnlimited) } }
        }
        .interactiveDismissDisabled(saving)
        .accessibilityIdentifier("food-analyze")
    }

    private var title: LocalizedStringKey {
        switch model.source {
        case .photo, .text: "nutrition.analyze.title"
        case .barcode, .search: "nutrition.product.title"
        }
    }

    // MARK: Phases

    private var describeInput: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.md) {
                Text("nutrition.describe.intro").font(DSFont.callout).foregroundStyle(DSColor.textSecondary)
                TextField("nutrition.describe.placeholder", text: $model.description, axis: .vertical)
                    .lineLimit(3...6).textFieldStyle(.roundedBorder).accessibilityIdentifier("food-describe-field")
                PrimaryButton("nutrition.describe.estimate", systemImage: "sparkles") { Task { await model.analyze() } }
                    .disabled(model.description.trimmingCharacters(in: .whitespacesAndNewlines).count < 2)
                    .accessibilityIdentifier("food-describe-submit")
                Text("nutrition.estimate.disclaimer").font(DSFont.footnote).foregroundStyle(DSColor.textTertiary)
            }
            .padding(Spacing.md)
        }
    }

    private var analyzing: some View {
        VStack(spacing: Spacing.lg) {
            photoPreview
            ProgressView().controlSize(.large)
            Text("nutrition.analyzing").font(DSFont.headline).foregroundStyle(DSColor.textPrimary)
            Text("nutrition.analyzing.detail").font(DSFont.footnote).foregroundStyle(DSColor.textSecondary)
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("food-analyzing")
    }

    @ViewBuilder
    private var photoPreview: some View {
        if case .photo(let jpeg, _) = model.source, let image = UIImage(data: jpeg) {
            Image(uiImage: image).resizable().scaledToFill().frame(maxWidth: .infinity).frame(height: 200)
                .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private func failure(_ error: FoodAnalyzeError) -> some View {
        VStack(spacing: Spacing.md) {
            switch error {
            case .quotaExceeded(let limit):
                if (limit ?? 0) > 3 {
                    // Pro already: no upsell, just the limit.
                    EmptyState(systemImage: "clock", title: "nutrition.error.quota.title", message: "nutrition.error.quota.pro.message")
                } else {
                    EmptyState(
                        systemImage: "lock.fill",
                        title: "nutrition.error.quota.title",
                        message: "nutrition.error.quota.message",
                        actionTitle: "paywall.seePro"
                    ) {
                        showsPaywall = true
                    }
                }
            case .rateLimited:
                EmptyState(
                    systemImage: "hourglass",
                    title: "nutrition.error.rate.title",
                    message: "nutrition.error.rate.message",
                    actionTitle: "common.retry"
                ) { retry() }
            case .notFood:
                EmptyState(systemImage: "questionmark.circle", title: "nutrition.error.notfood.title", message: "nutrition.error.notfood.message")
            case .consentRequired:
                EmptyState(systemImage: "hand.raised", title: "nutrition.error.consent.title", message: "nutrition.error.consent.message")
            case .offline:
                EmptyState(
                    systemImage: "wifi.slash",
                    title: "nutrition.error.offline.title",
                    message: "nutrition.error.offline.message",
                    actionTitle: "common.retry"
                ) { retry() }
            case .unauthorized, .unavailable, .timeout, .cancelled, .failed:
                EmptyState(
                    systemImage: "exclamationmark.triangle",
                    title: "nutrition.error.failed.title",
                    message: "nutrition.error.failed.message",
                    actionTitle: "common.retry"
                ) { retry() }
            }
            if model.source == .text, error == .notFood {
                SecondaryButton("nutrition.error.edit") { model.backToInput() }.padding(.horizontal, Spacing.md)
            }
        }
        .accessibilityIdentifier("food-failed")
    }

    private func retry() { Task { await model.analyze() } }

    // MARK: Editor

    private var editor: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.md) {
                photoPreview
                TextField("nutrition.editor.name", text: $model.mealName).font(DSFont.title).textFieldStyle(.plain)
                    .accessibilityIdentifier("food-name-field")
                // A menu, not segments: four long Turkish labels do not fit in 393 pt ("Akşam yem…").
                Picker("nutrition.editor.meal", selection: $model.meal) {
                    ForEach(MealType.allCases, id: \.self) { Text($0.titleKey).tag($0) }
                }
                .pickerStyle(.menu)
                DatePicker("nutrition.editor.time", selection: $model.eatenAt, in: ...Date(), displayedComponents: [.date, .hourAndMinute])
                if let notes = model.notes { Label(notes, systemImage: "info.circle").font(DSFont.footnote).foregroundStyle(DSColor.textSecondary) }
                ForEach(model.items) { item in itemCard(item) }
                totalsCard
                if let remaining = model.remaining, let limit = model.limit {
                    HStack(spacing: Spacing.xs) {
                        Text(verbatim: "\(remaining)/\(limit)").font(DSFont.numericSmall)
                        Text("nutrition.quota.left")
                    }
                    .font(DSFont.footnote).foregroundStyle(DSColor.textSecondary)
                }
                Text("nutrition.estimate.disclaimer").font(DSFont.footnote).foregroundStyle(DSColor.textTertiary)
                if saveFailed { Text("nutrition.save.failed").font(DSFont.footnote).foregroundStyle(DSColor.error) }
                PrimaryButton("nutrition.editor.save", systemImage: "checkmark", isLoading: saving) { save() }
                    .disabled(!model.canSave)
                    .accessibilityIdentifier("food-save")
            }
            .padding(Spacing.md)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private func itemCard(_ item: FoodItemDetail) -> some View {
        Card {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                HStack {
                    Text(item.name).font(DSFont.headline).foregroundStyle(DSColor.textPrimary)
                    Spacer()
                    Button(role: .destructive) { model.remove(item.id) } label: { Image(systemName: "trash") }
                        .accessibilityLabel(Text("nutrition.item.remove"))
                }
                NumberField(
                    title: "nutrition.item.grams", value: Binding(get: { item.grams }, set: { model.setGrams($0, for: item.id) }), unit: "g", maximum: 5000
                )
                HStack(spacing: Spacing.xs) {
                    Text(verbatim: "\(Int(item.calories.rounded()))")
                    Text("nutrition.unit.kcal")
                    Text(verbatim: "·")
                    MacroLine(protein: item.proteinG, carbs: item.carbsG, fat: item.fatG)
                }
                .font(DSFont.callout).foregroundStyle(DSColor.textSecondary)
            }
        }
    }

    private var totalsCard: some View {
        let totals = model.totals
        return Card {
            HStack {
                VStack(alignment: .leading) {
                    Text("nutrition.editor.total").font(DSFont.caption).foregroundStyle(DSColor.textSecondary)
                    HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
                        Text(verbatim: "\(Int(totals.calories.rounded()))").font(DSFont.numericLarge)
                        Text("nutrition.unit.kcal").font(DSFont.callout).foregroundStyle(DSColor.textSecondary)
                    }
                    .foregroundStyle(DSColor.textPrimary)
                }
                Spacer()
                MacroLine(protein: totals.proteinG, carbs: totals.carbsG, fat: totals.fatG)
                    .font(DSFont.numericSmall).foregroundStyle(DSColor.textSecondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("food-totals")
    }

    private func save() {
        saving = true
        saveFailed = false
        Task {
            let saved = await onSave(model.makeInput())
            saving = false
            if saved { onClose() } else { saveFailed = true }
        }
    }
}

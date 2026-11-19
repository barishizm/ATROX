import DataKit
import DesignSystem
import SwiftUI

/// Find a packaged product: scan its barcode, type the number, or search by name (Open Food Facts).
struct BarcodeLookupView: View {
    let service: any PackagedFoodService
    let languageCode: String
    let onSelect: (PackagedFood) -> Void
    let onClose: () -> Void

    private enum Mode: Hashable { case scan, search }

    @State private var mode: Mode = .scan
    @State private var manualCode = ""
    @State private var query = ""
    @State private var results: [PackagedFood] = []
    @State private var isLoading = false
    @State private var message: LocalizedStringKey?
    @State private var scanned = false

    var body: some View {
        NavigationStack {
            VStack(spacing: Spacing.md) {
                Picker("nutrition.barcode.mode", selection: $mode) {
                    Text("nutrition.barcode.scan").tag(Mode.scan)
                    Text("nutrition.barcode.search").tag(Mode.search)
                }
                .pickerStyle(.segmented)
                if mode == .scan { scanSection } else { searchSection }
                if isLoading { ProgressView() }
                if let message { Text(message).font(DSFont.footnote).foregroundStyle(DSColor.textSecondary).multilineTextAlignment(.center) }
                Text("nutrition.barcode.source").font(DSFont.caption).foregroundStyle(DSColor.textTertiary).multilineTextAlignment(.center)
            }
            .padding(Spacing.md)
            .frame(maxHeight: .infinity, alignment: .top)
            .background(DSColor.background.ignoresSafeArea())
            .navigationTitle("nutrition.barcode.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("common.cancel", action: onClose) } }
        }
        .accessibilityIdentifier("barcode-lookup")
    }

    private var scanSection: some View {
        VStack(spacing: Spacing.md) {
            if BarcodeScannerView.isSupported {
                BarcodeScannerView { code in
                    guard !scanned else { return }
                    scanned = true
                    Task { await lookup(code) }
                }
                .frame(height: 280).clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
                .accessibilityLabel(Text("nutrition.barcode.scanner.a11y"))
            }
            HStack {
                TextField("nutrition.barcode.number", text: $manualCode).keyboardType(.numberPad).textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("barcode-number")
                Button("nutrition.barcode.find") { Task { await lookup(manualCode) } }
                    .buttonStyle(.borderedProminent).tint(DSColor.accentFill)
                    .disabled(!OpenFoodFacts.isValidBarcode(manualCode))
                    .accessibilityIdentifier("barcode-find")
            }
        }
    }

    private var searchSection: some View {
        VStack(spacing: Spacing.sm) {
            HStack {
                TextField("nutrition.barcode.search.placeholder", text: $query).textFieldStyle(.roundedBorder).submitLabel(.search)
                    .onSubmit { Task { await search() } }.accessibilityIdentifier("barcode-search-field")
                Button("nutrition.barcode.search.go") { Task { await search() } }.buttonStyle(.borderedProminent).tint(DSColor.accentFill)
                    .disabled(query.trimmingCharacters(in: .whitespaces).count < 2)
            }
            ScrollView {
                LazyVStack(spacing: Spacing.xs) {
                    ForEach(results) { food in
                        Button { onSelect(food) } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(food.displayName).font(DSFont.callout).foregroundStyle(DSColor.textPrimary).lineLimit(2)
                                    Text(verbatim: "\(Int(food.caloriesPer100g.rounded())) kcal / 100 g").font(DSFont.caption).foregroundStyle(DSColor.textSecondary)
                                }
                                Spacer()
                                Image(systemName: "plus.circle").foregroundStyle(DSColor.accent)
                            }
                            .padding(Spacing.sm).frame(minHeight: HitTarget.minimum)
                            .background(DSColor.surface, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func lookup(_ code: String) async {
        let digits = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard OpenFoodFacts.isValidBarcode(digits) else {
            message = "nutrition.barcode.invalid"
            scanned = false
            return
        }
        isLoading = true
        message = nil
        defer { isLoading = false }
        do {
            if let food = try await service.product(barcode: digits) {
                onSelect(food)
            } else {
                message = "nutrition.barcode.notfound"
                scanned = false
            }
        } catch {
            message = "nutrition.barcode.error"
            scanned = false
        }
    }

    private func search() async {
        isLoading = true
        message = nil
        defer { isLoading = false }
        do {
            results = try await service.search(query, languageCode: languageCode)
            if results.isEmpty { message = "nutrition.barcode.noresults" }
        } catch {
            message = "nutrition.barcode.error"
        }
    }
}

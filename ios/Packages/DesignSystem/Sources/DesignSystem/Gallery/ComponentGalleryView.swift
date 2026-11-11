import SwiftUI

/// Developer-only catalog of every token and component. The app shows it exclusively in Debug
/// builds (`#if DEBUG`). Strings here are intentionally not localized.
public struct ComponentGalleryView: View {
    @State private var appearance: AppearancePreference = .dark
    @State private var score: Double = 73
    @State private var ringID = 0
    @State private var isLoadingButton = false

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                Picker("Tema", selection: $appearance) {
                    ForEach(AppearancePreference.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                }
                .pickerStyle(.segmented)

                section("Skor Halkası") {
                    Card {
                        VStack(spacing: Spacing.md) {
                            ScoreRing(score: score).id(ringID).frame(maxWidth: .infinity)
                            Slider(value: $score, in: 0...100)
                            SecondaryButton("0 → 73 animasyonunu oynat", systemImage: "play.fill") {
                                score = 73
                                ringID += 1
                            }
                        }
                    }
                    levelRow
                }

                section("Butonlar") {
                    PrimaryButton("Antrenmanı Başlat", systemImage: "play.fill") {}
                    PrimaryButton("Kaydet", isLoading: isLoadingButton) {
                        isLoadingButton = true
                        Task {
                            try? await Task.sleep(for: .seconds(1.5))
                            isLoadingButton = false
                        }
                    }
                    SecondaryButton("Şablon Seç", systemImage: "list.bullet") {}
                }

                section("Metrikler") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: Spacing.md)], spacing: Spacing.md) {
                        StatTile("Hacim", value: "12.480", unit: "kg", delta: .init("+4,2%", direction: .up))
                        StatTile("Seri", value: "18", delta: .init("−2", direction: .down))
                    }
                }

                section("Etiketler") {
                    HStack { TagChip("Göğüs"); TagChip("PR", systemImage: "trophy.fill", style: .accent) }
                    HStack { TagChip("OK", style: .success); TagChip("Uyarı", style: .warning); TagChip("Hata", style: .error) }
                }

                section("Başlık") {
                    SectionHeader("Son Antrenmanlar", subtitle: "Son 30 gün", actionTitle: "Tümü") {}
                }

                section("Durumlar") {
                    Card { EmptyState(systemImage: "dumbbell.fill", title: "Henüz antrenman yok", message: "İlk antrenmanını kaydet.", actionTitle: "Başlat") {} }
                    Card { LoadingState() }
                    Card { ErrorState(message: "Bağlantı kurulamadı.") {} }
                }

                section("Renkler") { swatches }

                section("Tipografi") {
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        Text(verbatim: "128,5").font(DSFont.display)
                        Text(verbatim: "Başlık").font(DSFont.title)
                        Text(verbatim: "Headline").font(DSFont.headline)
                        Text(verbatim: "Body metni").font(DSFont.body)
                        Text(verbatim: "Callout").font(DSFont.callout)
                        Text(verbatim: "Caption").font(DSFont.caption)
                        Text(verbatim: "Overline").dsOverline()
                    }
                    .foregroundStyle(DSColor.textPrimary)
                }

                section("Haptics") {
                    FlowRow {
                        ForEach(Haptics.Kind.allCases, id: \.self) { kind in
                            SecondaryButton(LocalizedStringKey("\(String(describing: kind))")) { Haptics.play(kind) }
                        }
                    }
                }
            }
            .padding(Spacing.md)
        }
        .background(DSColor.background)
        .navigationTitle("Bileşen Galerisi")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .preferredColorScheme(appearance.colorScheme)
        .accessibilityIdentifier("component-gallery")
    }

    private func section<C: View>(_ title: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text(verbatim: title).dsOverline()
            content()
        }
    }

    private var levelRow: some View {
        HStack(spacing: Spacing.md) {
            ForEach(ScoreLevel.allCases, id: \.self) { l in
                ScoreRing(score: [10, 30, 50, 70, 88, 97][l.rawValue], diameter: 44, lineWidth: 5, showsLevel: false)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var swatches: some View {
        let items: [(String, Color)] = [
            ("background", DSColor.background), ("surface", DSColor.surface),
            ("raised", DSColor.surfaceRaised), ("overlay", DSColor.surfaceOverlay),
            ("accent", DSColor.accent), ("success", DSColor.success),
            ("warning", DSColor.warning), ("error", DSColor.error)
        ]
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: Spacing.sm)], spacing: Spacing.sm) {
            ForEach(items, id: \.0) { name, color in
                VStack(spacing: Spacing.xs) {
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .fill(color)
                        .frame(height: 44)
                        .overlay(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous).strokeBorder(DSColor.separator))
                    Text(verbatim: name).font(DSFont.caption).foregroundStyle(DSColor.textSecondary)
                }
            }
        }
    }
}

private struct FlowRow<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: Spacing.sm)], spacing: Spacing.sm) { content }
    }
}

#Preview("Dark") { NavigationStack { ComponentGalleryView() } }
#Preview("Light") { NavigationStack { ComponentGalleryView() }.preferredColorScheme(.light) }

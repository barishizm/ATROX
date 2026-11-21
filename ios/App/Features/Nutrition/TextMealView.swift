import DesignSystem
import SwiftUI

/// "Tell us what you're having": a typed or dictated description that the AI turns into a logged meal.
struct TextMealView: View {
    /// The longest description the server accepts (food-analyze schema).
    static let maxLength = 300

    @Binding var text: String
    let onAnalyze: () -> Void

    @Environment(\.locale) private var locale
    @State private var dictation = MealDictation()
    @State private var baseText = ""
    @FocusState private var focused: Bool

    private var trimmedCount: Int { text.trimmingCharacters(in: .whitespacesAndNewlines).count }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("nutrition.text.title").font(DSFont.title).foregroundStyle(DSColor.textPrimary)
            editor
            if dictation.state == .denied {
                Text("nutrition.text.mic.denied").font(DSFont.footnote).foregroundStyle(DSColor.warning)
            }
            Spacer(minLength: 0)
            PrimaryButton("nutrition.text.analyze", systemImage: "sparkles") {
                dictation.stop()
                onAnalyze()
            }
            .disabled(trimmedCount < 2)
            .accessibilityIdentifier("text-meal-analyze")
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(DSColor.background.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { focused = true }
        .onDisappear { dictation.stop() }
        .onChange(of: text) { _, new in if new.count > Self.maxLength { text = String(new.prefix(Self.maxLength)) } }
        .onChange(of: dictation.transcript) { _, spoken in
            guard dictation.isListening, !spoken.isEmpty else { return }
            let joined = baseText.isEmpty ? spoken : baseText + " " + spoken
            text = String(joined.prefix(Self.maxLength))
        }
        .accessibilityIdentifier("text-meal")
    }

    private var editor: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $text)
                .focused($focused).scrollContentBackground(.hidden).font(DSFont.body).foregroundStyle(DSColor.textPrimary)
                .padding(.horizontal, Spacing.xs).padding(.top, Spacing.xs).padding(.bottom, 56)
                .accessibilityIdentifier("text-meal-field")
            if text.isEmpty {
                Text("nutrition.text.placeholder").font(DSFont.body).foregroundStyle(DSColor.textTertiary)
                    .padding(.horizontal, Spacing.sm + 4).padding(.top, Spacing.sm + 2).allowsHitTesting(false)
            }
        }
        .frame(height: 220)
        .background(DSColor.surface, in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .overlay(alignment: .bottom) {
            HStack {
                Text("nutrition.text.left \(Self.maxLength - text.count)").font(DSFont.footnote).foregroundStyle(DSColor.textSecondary)
                Spacer()
                micButton
            }
            .padding(Spacing.sm)
        }
    }

    private var micButton: some View {
        Button {
            if !dictation.isListening { baseText = text.trimmingCharacters(in: .whitespacesAndNewlines) }
            Task { await dictation.toggle(locale: locale) }
        } label: {
            Image(systemName: dictation.isListening ? "stop.fill" : "mic.fill").font(.title3).foregroundStyle(DSColor.accent)
                .frame(width: 44, height: 44).glassEffect(Glass.regular.tint(dictation.isListening ? DSColor.accentFill : .clear).interactive(), in: Circle())
                .symbolEffect(.pulse, isActive: dictation.isListening)
        }
        .accessibilityLabel(Text(dictation.isListening ? "nutrition.text.mic.stop" : "nutrition.text.mic"))
        .accessibilityIdentifier("text-meal-mic")
    }
}

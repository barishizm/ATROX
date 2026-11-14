import DesignSystem
import SwiftUI

/// Preview, what-to-show switches and the share buttons (P084).
struct ShareCardSheet: View {
    let content: ShareCardContent
    @Environment(\.locale) private var locale
    @Environment(\.dismiss) private var dismiss
    @State private var options = ShareCardOptions()
    @State private var image: UIImage?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.lg) {
                    Picker("share.format", selection: $options.format) {
                        Text("share.format.story").tag(ShareCardOptions.Format.story)
                        Text("share.format.square").tag(ShareCardOptions.Format.square)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("share-format")

                    preview
                    switches
                    actions
                }
                .padding(Spacing.md)
            }
            .background(DSColor.background)
            .navigationTitle("share.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("share.close") { dismiss() } }
            }
            .task(id: options) { image = ShareCardRenderer.image(content: content, options: options, locale: locale) }
        }
        .accessibilityIdentifier("share-sheet")
    }

    private var preview: some View {
        let size = options.format.size
        let width: CGFloat = 280  // fits the narrowest iPhone with margins
        let scale = width / size.width
        return ShareCardView(content: content, options: options)
            .environment(\.locale, locale)
            .frame(width: size.width, height: size.height)
            .scaleEffect(scale, anchor: .topLeading)
            .frame(width: width, height: size.height * scale)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .accessibilityLabel(Text("share.preview.a11y"))
    }

    @ViewBuilder private var switches: some View {
        VStack(spacing: Spacing.xs) {
            if let name = content.displayName, !name.isEmpty {
                Toggle("share.option.name", isOn: $options.showsName)
            }
            if content.bodyweightText != nil {
                Toggle("share.option.bodyweight", isOn: $options.showsBodyweight)
            }
            if content.referenceLabel != nil {
                Toggle("share.option.reference", isOn: $options.showsReference)
            }
        }
        .tint(DSColor.accent)
    }

    @ViewBuilder private var actions: some View {
        if let image {
            VStack(spacing: Spacing.sm) {
                ShareLink(
                    item: Image(uiImage: image),
                    preview: SharePreview(Text("share.title"), image: Image(uiImage: image))
                ) {
                    Label("share.action", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(DSColor.accent)
                .accessibilityIdentifier("share-link")
                if InstagramStories.isAvailable {
                    Button {
                        InstagramStories.share(image)
                    } label: {
                        Label("share.instagram", systemImage: "camera").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("share-instagram")
                }
            }
        } else {
            ProgressView()
        }
    }
}

/// A toolbar / inline button that opens the share sheet for `content`.
struct ShareCardButton: View {
    let content: ShareCardContent?
    @State private var isPresented = false

    var body: some View {
        if let content {
            Button {
                isPresented = true
            } label: {
                Label("share.action", systemImage: "square.and.arrow.up")
            }
            .accessibilityIdentifier("share-card-button")
            .sheet(isPresented: $isPresented) { ShareCardSheet(content: content) }
        }
    }
}

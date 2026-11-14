import DesignSystem
import SwiftUI

/// Renders the coach's Markdown (paragraphs, lists, tables, code) in the app's type scale.
struct MarkdownTextView: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            ForEach(Array(MarkdownBlocks.parse(text).enumerated()), id: \.offset) { _, block in
                view(for: block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func view(for block: MarkdownBlock) -> some View {
        switch block {
        case .paragraph(let value):
            inline(value).font(DSFont.body)
        case .heading(let value):
            inline(value).font(DSFont.headline).accessibilityAddTraits(.isHeader)
        case .bullets(let items):
            VStack(alignment: .leading, spacing: Spacing.xs) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                        Text(verbatim: "•").accessibilityHidden(true)
                        inline(item)
                    }
                    .font(DSFont.body)
                }
            }
        case .numbered(let items):
            VStack(alignment: .leading, spacing: Spacing.xs) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                        Text(verbatim: "\(index + 1).").monospacedDigit()
                        inline(item)
                    }
                    .font(DSFont.body)
                }
            }
        case .table(let header, let rows):
            table(header: header, rows: rows)
        case .code(let value):
            ScrollView(.horizontal, showsIndicators: false) {
                Text(verbatim: value).font(.system(.callout, design: .monospaced)).padding(Spacing.sm)
            }
            .background(DSColor.surfaceRaised, in: RoundedRectangle(cornerRadius: Radius.sm))
        }
    }

    private func table(header: [String], rows: [[String]]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Grid(alignment: .leading, horizontalSpacing: Spacing.md, verticalSpacing: Spacing.xs) {
                GridRow {
                    ForEach(Array(header.enumerated()), id: \.offset) { _, cell in
                        inline(cell).font(DSFont.callout.weight(.semibold))
                    }
                }
                Divider()
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    GridRow {
                        ForEach(Array(row.enumerated()), id: \.offset) { _, cell in inline(cell).font(DSFont.callout) }
                    }
                }
            }
            .padding(Spacing.sm)
        }
        .background(DSColor.surfaceRaised, in: RoundedRectangle(cornerRadius: Radius.sm))
    }

    /// Bold, italic, code and links inside one block.
    private func inline(_ value: String) -> Text {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        if let attributed = try? AttributedString(markdown: value, options: options) { return Text(attributed) }
        return Text(verbatim: value)
    }
}

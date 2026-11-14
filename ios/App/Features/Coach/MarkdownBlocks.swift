import Foundation

/// The Markdown the coach uses: paragraphs, headings, bullet and numbered lists, tables and code blocks. Inline styling
/// (bold, italic, code, links) is left to `AttributedString(markdown:)` per block.
enum MarkdownBlock: Equatable {
    case paragraph(String)
    case heading(String)
    case bullets([String])
    case numbered([String])
    case table(header: [String], rows: [[String]])
    case code(String)
}

enum MarkdownBlocks {
    static func parse(_ text: String) -> [MarkdownBlock] {
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var blocks: [MarkdownBlock] = []
        var paragraph: [String] = []
        var index = 0

        func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            blocks.append(.paragraph(paragraph.joined(separator: "\n")))
            paragraph = []
        }

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                flushParagraph()
                var code: [String] = []
                index += 1
                while index < lines.count, !lines[index].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    code.append(lines[index])
                    index += 1
                }
                blocks.append(.code(code.joined(separator: "\n")))
            } else if trimmed.isEmpty {
                flushParagraph()
            } else if let heading = headingText(trimmed) {
                flushParagraph()
                blocks.append(.heading(heading))
            } else if isTableRow(trimmed) {
                flushParagraph()
                var rows: [String] = []
                while index < lines.count, isTableRow(lines[index].trimmingCharacters(in: .whitespaces)) {
                    rows.append(lines[index].trimmingCharacters(in: .whitespaces))
                    index += 1
                }
                index -= 1
                blocks.append(table(rows))
            } else if bulletText(trimmed) != nil {
                flushParagraph()
                var items: [String] = []
                while index < lines.count, let item = bulletText(lines[index].trimmingCharacters(in: .whitespaces)) {
                    items.append(item)
                    index += 1
                }
                index -= 1
                blocks.append(.bullets(items))
            } else if numberedText(trimmed) != nil {
                flushParagraph()
                var items: [String] = []
                while index < lines.count, let item = numberedText(lines[index].trimmingCharacters(in: .whitespaces)) {
                    items.append(item)
                    index += 1
                }
                index -= 1
                blocks.append(.numbered(items))
            } else {
                paragraph.append(trimmed)
            }
            index += 1
        }
        flushParagraph()
        return blocks
    }

    private static func headingText(_ line: String) -> String? {
        guard line.hasPrefix("#") else { return nil }
        let text = line.drop(while: { $0 == "#" })
        guard text.first == " " else { return nil }
        return text.trimmingCharacters(in: .whitespaces)
    }

    private static func bulletText(_ line: String) -> String? {
        for marker in ["- ", "* ", "• "] where line.hasPrefix(marker) { return String(line.dropFirst(marker.count)) }
        return nil
    }

    private static func numberedText(_ line: String) -> String? {
        let digits = line.prefix(while: \.isNumber)
        guard !digits.isEmpty, digits.count <= 3 else { return nil }
        let rest = line.dropFirst(digits.count)
        guard rest.hasPrefix(". ") || rest.hasPrefix(") ") else { return nil }
        return String(rest.dropFirst(2))
    }

    private static func isTableRow(_ line: String) -> Bool { line.hasPrefix("|") && line.dropFirst().contains("|") }

    private static func cells(_ row: String) -> [String] {
        var parts = row.split(separator: "|", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
        if parts.first == "" { parts.removeFirst() }
        if parts.last == "" { parts.removeLast() }
        return parts
    }

    private static func isSeparator(_ row: String) -> Bool {
        let content = cells(row)
        return !content.isEmpty && content.allSatisfy { cell in
            !cell.isEmpty && cell.allSatisfy { $0 == "-" || $0 == ":" || $0 == " " } && cell.contains("-")
        }
    }

    private static func table(_ rows: [String]) -> MarkdownBlock {
        let body = rows.filter { !isSeparator($0) }.map(cells)
        guard let header = body.first else { return .paragraph(rows.joined(separator: "\n")) }
        return .table(header: header, rows: Array(body.dropFirst()))
    }
}

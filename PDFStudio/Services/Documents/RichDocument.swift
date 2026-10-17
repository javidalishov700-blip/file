import Foundation

/// A piece of text with simple formatting.
struct TextRun: Equatable {
    var text: String
    var bold = false
    var italic = false
    var code = false
    var link: String? = nil
}

/// Format-neutral document structure every reader produces and every writer consumes,
/// so any supported input can become any supported text output (Markdown → Word, Excel → CSV …).
enum DocBlock: Equatable {
    case heading(level: Int, runs: [TextRun])
    case paragraph([TextRun])
    case listItem(ordered: Bool, number: Int, level: Int, runs: [TextRun])
    case quote([TextRun])
    case code(String)
    /// The first row is the header.
    case table([[String]])
    case rule
    case pageBreak
}

struct RichDocument {
    var title: String
    var blocks: [DocBlock]

    var tables: [[[String]]] {
        blocks.compactMap { block -> [[String]]? in
            if case .table(let rows) = block { return rows }
            return nil
        }
    }

    var hasText: Bool {
        blocks.contains { block in
            switch block {
            case .heading(_, let runs), .paragraph(let runs), .quote(let runs), .listItem(_, _, _, let runs):
                return !runs.plain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            case .code(let text):
                return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            case .table(let rows):
                return rows.contains { $0.contains { !$0.isEmpty } }
            case .rule, .pageBreak:
                return false
            }
        }
    }

    /// Plain text where every non-empty line is a paragraph.
    static func plain(_ text: String, title: String) -> RichDocument {
        let blocks = text.replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .map { DocBlock.paragraph([TextRun(text: $0)]) }
        return RichDocument(title: title, blocks: blocks)
    }

    /// Pages of extracted PDF text, wrapped lines joined back into paragraphs.
    static func pages(_ pages: [String], title: String) -> RichDocument {
        var blocks: [DocBlock] = []
        for (index, page) in pages.enumerated() {
            if index > 0 { blocks.append(.pageBreak) }
            blocks += TextExtractor.paragraphs(page).map { .paragraph([TextRun(text: $0)]) }
        }
        return RichDocument(title: title, blocks: blocks)
    }
}

extension Array where Element == TextRun {
    var plain: String { map(\.text).joined() }
}

/// Reads text files in UTF-8/UTF-16 (with BOM) or, failing that, the Turkish Windows code page.
func readTextFile(_ url: URL) throws -> String {
    var encoding = String.Encoding.utf8
    if let text = try? String(contentsOf: url, usedEncoding: &encoding) { return text }
    if let text = try? String(contentsOf: url, encoding: .utf8) { return text }
    if let text = try? String(contentsOf: url, encoding: .windowsCP1254) { return text }
    throw PDFToolError.unreadable(url.lastPathComponent)
}

import Foundation

/// Reads the text and structure of .docx files (headings, bold/italic, lists, quotes, tables).
enum DocxReader {
    static func read(_ data: Data, title: String) throws -> RichDocument {
        let zip = try ZipReader(data: data)
        guard let xml = zip.entries["word/document.xml"] else { throw PDFToolError.message("This is not a valid Word document.") }
        let parser = DocxParser()
        let xmlParser = XMLParser(data: xml)
        xmlParser.delegate = parser
        xmlParser.parse()
        return RichDocument(title: title, blocks: parser.blocks)
    }
}

private final class DocxParser: NSObject, XMLParserDelegate {
    var blocks: [DocBlock] = []

    private var paragraphDepth = 0
    private var runs: [TextRun] = []
    private var style = ""
    private var outlineLevel: Int?
    private var isList = false
    private var listLevel = 0
    private var pendingPageBreak = false

    private var inRun = false
    private var inRunProperties = false
    private var bold = false
    private var italic = false
    private var inText = false
    private var text = ""

    private var tableDepth = 0
    private var rows: [[String]] = []
    private var row: [String] = []
    private var cell: [String] = []

    private func isOff(_ attributes: [String: String]) -> Bool {
        ["0", "false", "off"].contains(attributes["w:val"] ?? "")
    }

    private func appendText(_ string: String) {
        if let last = runs.last, last.bold == bold, last.italic == italic {
            runs[runs.count - 1].text += string
        } else {
            runs.append(TextRun(text: string, bold: bold, italic: italic))
        }
    }

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?,
                attributes: [String: String] = [:]) {
        switch name {
        case "w:p":
            paragraphDepth += 1
            if paragraphDepth == 1 {
                runs = []; style = ""; outlineLevel = nil; isList = false; listLevel = 0
            }
        case "w:pStyle": style = attributes["w:val"] ?? ""
        case "w:outlineLvl": outlineLevel = Int(attributes["w:val"] ?? "")
        case "w:numPr": isList = true
        case "w:ilvl": listLevel = Int(attributes["w:val"] ?? "0") ?? 0
        case "w:r": inRun = true; bold = false; italic = false
        case "w:rPr": inRunProperties = true
        case "w:b": if inRun && inRunProperties { bold = !isOff(attributes) }
        case "w:i": if inRun && inRunProperties { italic = !isOff(attributes) }
        case "w:t": inText = true; text = ""
        case "w:tab": if inRun { appendText("\t") }
        case "w:br":
            if attributes["w:type"] == "page" { pendingPageBreak = true } else if inRun { appendText("\n") }
        case "w:tbl":
            tableDepth += 1
            if tableDepth == 1 { rows = [] }
        case "w:tr": if tableDepth == 1 { row = [] }
        case "w:tc": if tableDepth == 1 { cell = [] }
        default: break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inText { text += string }
    }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        switch name {
        case "w:t": inText = false; appendText(text)
        case "w:rPr": inRunProperties = false
        case "w:r": inRun = false
        case "w:p":
            paragraphDepth -= 1
            if paragraphDepth == 0 { finishParagraph() }
        case "w:tc": if tableDepth == 1 { row.append(cell.joined(separator: " ")) }
        case "w:tr": if tableDepth == 1 { rows.append(row) }
        case "w:tbl":
            tableDepth -= 1
            if tableDepth == 0 {
                let width = rows.map(\.count).max() ?? 0
                if width > 0 { blocks.append(.table(rows.map { $0 + Array(repeating: "", count: width - $0.count) })) }
            }
        default: break
        }
    }

    private func finishParagraph() {
        let plain = runs.plain.trimmingCharacters(in: .whitespacesAndNewlines)
        if tableDepth > 0 {
            if !plain.isEmpty { cell.append(plain) }
            return
        }
        if pendingPageBreak {
            if !blocks.isEmpty { blocks.append(.pageBreak) }
            pendingPageBreak = false
        }
        guard !plain.isEmpty else { return }
        let lower = style.lowercased()
        var level: Int?
        if lower.hasPrefix("heading"), let n = Int(lower.dropFirst(7)) { level = n }
        if lower == "title" { level = 1 }
        if lower == "subtitle" { level = 2 }
        if level == nil, let outlineLevel, outlineLevel < 9 { level = outlineLevel + 1 }

        if let level {
            blocks.append(.heading(level: min(max(level, 1), 6), runs: runs.map { var run = $0; run.bold = false; return run }))
        } else if lower.contains("quote") {
            blocks.append(.quote(runs))
        } else if isList || lower.hasPrefix("list") {
            blocks.append(.listItem(ordered: lower.contains("number"), number: 1, level: listLevel, runs: runs))
        } else if let first = runs.first, first.text.hasPrefix("•\t") || first.text.hasPrefix("• ") {
            var rest = runs
            rest[0].text = String(first.text.dropFirst(2))
            blocks.append(.listItem(ordered: false, number: 0, level: 0, runs: rest.filter { !$0.text.isEmpty }))
        } else {
            blocks.append(.paragraph(runs))
        }
    }
}

/// Reads every worksheet of an .xlsx file as a table.
enum XlsxReader {
    static func read(_ data: Data) throws -> [(name: String, rows: [[String]])] {
        let zip = try ZipReader(data: data)
        let shared = zip.entries["xl/sharedStrings.xml"].map { SimpleXML.collect($0, item: "si", text: ["t"], skip: ["rPh"]) } ?? []
        let names = zip.entries["xl/workbook.xml"].map { SimpleXML.attributes($0, element: "sheet", attribute: "name") } ?? []
        let sheetPaths = zip.entries.keys
            .filter { $0.hasPrefix("xl/worksheets/sheet") && $0.hasSuffix(".xml") }
            .sorted { number(in: $0) < number(in: $1) }
        guard !sheetPaths.isEmpty else { throw PDFToolError.message("This is not a valid Excel file.") }

        return sheetPaths.enumerated().compactMap { index, path in
            guard let xml = zip.entries[path] else { return nil }
            let parser = SheetParser(shared: shared)
            let xmlParser = XMLParser(data: xml)
            xmlParser.delegate = parser
            xmlParser.parse()
            let rows = parser.table()
            guard !rows.isEmpty else { return nil }
            return (index < names.count ? names[index] : "Sheet\(index + 1)", rows)
        }
    }

    private static func number(in path: String) -> Int {
        Int(path.filter(\.isNumber)) ?? 0
    }

    static func columnIndex(_ reference: String) -> Int? {
        let letters = reference.prefix { $0.isLetter }.uppercased()
        guard !letters.isEmpty else { return nil }
        return letters.unicodeScalars.reduce(0) { $0 * 26 + Int($1.value) - 64 } - 1
    }
}

private final class SheetParser: NSObject, XMLParserDelegate {
    private let shared: [String]
    private var rows: [Int: [Int: String]] = [:]
    private var rowIndex = 0
    private var column = 0
    private var type = ""
    private var value = ""
    private var inValue = false

    init(shared: [String]) { self.shared = shared }

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?,
                attributes: [String: String] = [:]) {
        switch name {
        case "row":
            rowIndex = (Int(attributes["r"] ?? "") ?? (rowIndex + 1))
            column = -1
        case "c":
            column = attributes["r"].flatMap(XlsxReader.columnIndex) ?? (column + 1)
            type = attributes["t"] ?? ""
            value = ""
        case "v", "t": inValue = true
        default: break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inValue { value += string }
    }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        switch name {
        case "v", "t": inValue = false
        case "c":
            var text = value
            if type == "s", let index = Int(value), index < shared.count { text = shared[index] }
            if type == "b" { text = value == "1" ? "TRUE" : "FALSE" }
            if !text.isEmpty { rows[rowIndex, default: [:]][column] = text }
        default: break
        }
    }

    func table() -> [[String]] {
        guard let lastRow = rows.keys.max(), let firstRow = rows.keys.min() else { return [] }
        let width = (rows.values.flatMap(\.keys).max() ?? -1) + 1
        return (firstRow...lastRow).map { r in (0..<width).map { rows[r]?[$0] ?? "" } }
    }
}

/// Reads the text on each slide of a .pptx presentation.
enum PptxReader {
    static func read(_ data: Data, title: String) throws -> RichDocument {
        let zip = try ZipReader(data: data)
        let slides = zip.entries.keys
            .filter { $0.hasPrefix("ppt/slides/slide") && $0.hasSuffix(".xml") }
            .sorted { (Int($0.filter(\.isNumber)) ?? 0) < (Int($1.filter(\.isNumber)) ?? 0) }
        guard !slides.isEmpty else { throw PDFToolError.message("This is not a valid PowerPoint file.") }
        var blocks: [DocBlock] = []
        for (index, path) in slides.enumerated() {
            guard let xml = zip.entries[path] else { continue }
            let paragraphs = SimpleXML.collect(xml, item: "a:p", text: ["a:t"], skip: [])
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            if index > 0 { blocks.append(.pageBreak) }
            let heading = paragraphs.first.map { "Slide \(index + 1): \($0)" } ?? "Slide \(index + 1)"
            blocks.append(.heading(level: 2, runs: [TextRun(text: heading)]))
            blocks += paragraphs.dropFirst().map { .paragraph([TextRun(text: $0)]) }
        }
        return RichDocument(title: title, blocks: blocks)
    }
}

/// Small helpers for pulling text and attributes out of XML parts.
enum SimpleXML {
    /// The concatenated text of `text` elements inside each `item` element.
    static func collect(_ data: Data, item: String, text: Set<String>, skip: Set<String>) -> [String] {
        let collector = Collector(item: item, text: text, skip: skip)
        let parser = XMLParser(data: data)
        parser.delegate = collector
        parser.parse()
        return collector.items
    }

    static func attributes(_ data: Data, element: String, attribute: String) -> [String] {
        let collector = AttributeCollector(element: element, attribute: attribute)
        let parser = XMLParser(data: data)
        parser.delegate = collector
        parser.parse()
        return collector.values
    }

    private final class Collector: NSObject, XMLParserDelegate {
        let item: String, text: Set<String>, skip: Set<String>
        var items: [String] = []
        private var current: String?
        private var inText = false
        private var skipDepth = 0

        init(item: String, text: Set<String>, skip: Set<String>) {
            self.item = item; self.text = text; self.skip = skip
        }

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?,
                    attributes: [String: String] = [:]) {
            if name == item { current = "" }
            if skip.contains(name) { skipDepth += 1 }
            if text.contains(name), skipDepth == 0 { inText = true }
            if name == "a:br", current != nil { current? += " " }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            if inText { current? += string }
        }

        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
            if text.contains(name) { inText = false }
            if skip.contains(name) { skipDepth -= 1 }
            if name == item, let value = current {
                items.append(value)
                current = nil
            }
        }
    }

    private final class AttributeCollector: NSObject, XMLParserDelegate {
        let element: String, attribute: String
        var values: [String] = []
        init(element: String, attribute: String) { self.element = element; self.attribute = attribute }

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?,
                    attributes: [String: String] = [:]) {
            if name == element, let value = attributes[attribute] { values.append(value) }
        }
    }
}

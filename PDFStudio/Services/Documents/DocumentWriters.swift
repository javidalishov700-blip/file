import UIKit

enum HTMLWriter {
    static func write(_ document: RichDocument) -> String {
        var body: [String] = []
        var openList: (ordered: Bool, level: Int)?

        func closeList() {
            if let list = openList { body.append(list.ordered ? "</ol>" : "</ul>") }
            openList = nil
        }

        for block in document.blocks {
            if case .listItem(let ordered, let number, let level, let runs) = block {
                if openList == nil || openList!.ordered != ordered || openList!.level != level {
                    closeList()
                    let indent = level > 0 ? " style=\"margin-left:\(Double(level) * 1.5)em\"" : ""
                    body.append(ordered ? "<ol start=\"\(number)\"\(indent)>" : "<ul\(indent)>")
                    openList = (ordered, level)
                }
                body.append("<li>\(inline(runs))</li>")
                continue
            }
            closeList()
            switch block {
            case .heading(let level, let runs): body.append("<h\(level)>\(inline(runs))</h\(level)>")
            case .paragraph(let runs): body.append("<p>\(inline(runs))</p>")
            case .quote(let runs): body.append("<blockquote>\(inline(runs))</blockquote>")
            case .code(let text): body.append("<pre><code>\(escape(text))</code></pre>")
            case .table(let rows):
                guard let header = rows.first else { continue }
                var html = "<table>\n<thead><tr>" + header.map { "<th>\(escape($0))</th>" }.joined() + "</tr></thead>\n<tbody>\n"
                html += rows.dropFirst().map { "<tr>" + $0.map { "<td>\(escape($0))</td>" }.joined() + "</tr>" }.joined(separator: "\n")
                body.append(html + "\n</tbody>\n</table>")
            case .rule: body.append("<hr>")
            case .pageBreak: body.append("<div class=\"page-break\"></div>")
            case .listItem: break
            }
        }
        closeList()

        return """
        <!doctype html>
        <html lang="en"><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>\(escape(document.title))</title>
        <style>
        body{font-family:-apple-system,"Helvetica Neue",Arial,sans-serif;font-size:15px;line-height:1.55;color:#1c1c1e;max-width:46rem;margin:2rem auto;padding:0 1rem}
        h1,h2,h3,h4{line-height:1.25;margin:1.4em 0 .5em}
        pre{background:#f2f2f7;padding:12px 14px;border-radius:8px;overflow-x:auto;font-size:13px}
        code{font-family:Menlo,Consolas,monospace;background:#f2f2f7;padding:1px 4px;border-radius:4px}
        pre code{background:none;padding:0}
        blockquote{border-left:4px solid #d1d1d6;margin:1em 0;padding:.2em 1em;color:#555}
        table{border-collapse:collapse;margin:1em 0;font-size:14px;width:100%}
        th,td{border:1px solid #c7c7cc;padding:6px 10px;text-align:left;vertical-align:top}
        th{background:#f2f2f7}
        hr{border:none;border-top:1px solid #d1d1d6;margin:2em 0}
        .page-break{page-break-after:always;break-after:page}
        a{color:#0a84ff}
        </style></head><body>
        \(body.joined(separator: "\n"))
        </body></html>
        """
    }

    static func inline(_ runs: [TextRun]) -> String {
        runs.map { run in
            var html = escape(run.text).replacingOccurrences(of: "\n", with: "<br>")
            if run.code { html = "<code>\(html)</code>" }
            if run.italic { html = "<em>\(html)</em>" }
            if run.bold { html = "<strong>\(html)</strong>" }
            if let link = run.link { html = "<a href=\"\(escape(link))\">\(html)</a>" }
            return html
        }.joined()
    }

    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}

enum PlainTextWriter {
    static func write(_ document: RichDocument) -> String {
        var out: [String] = []
        for block in document.blocks {
            switch block {
            case .heading(_, let runs), .paragraph(let runs): out.append(runs.plain)
            case .quote(let runs): out.append("“\(runs.plain)”")
            case .listItem(let ordered, let number, let level, let runs):
                out.append(String(repeating: "    ", count: level) + (ordered ? "\(number). " : "• ") + runs.plain)
            case .code(let text): out.append(text)
            case .table(let rows): out.append(rows.map { $0.joined(separator: "\t") }.joined(separator: "\n"))
            case .rule: out.append("————————")
            case .pageBreak: out.append("")
            }
        }
        return out.joined(separator: "\n\n") + "\n"
    }
}

enum RTFWriter {
    static func write(_ document: RichDocument) throws -> Data {
        let output = NSMutableAttributedString()
        let body = NSMutableParagraphStyle()
        body.paragraphSpacing = 8

        func font(size: CGFloat, bold: Bool, italic: Bool, code: Bool) -> UIFont {
            if code { return UIFont(name: "Courier", size: size) ?? .monospacedSystemFont(ofSize: size, weight: .regular) }
            let name = bold && italic ? "Helvetica-BoldOblique" : bold ? "Helvetica-Bold" : italic ? "Helvetica-Oblique" : "Helvetica"
            return UIFont(name: name, size: size) ?? .systemFont(ofSize: size)
        }

        func append(_ runs: [TextRun], size: CGFloat = 12, forceBold: Bool = false, italic forceItalic: Bool = false,
                    style: NSParagraphStyle = body, prefix: String = "") {
            if !prefix.isEmpty {
                output.append(NSAttributedString(string: prefix, attributes: [.font: font(size: size, bold: false, italic: false, code: false),
                                                                              .paragraphStyle: style]))
            }
            for run in runs {
                var attributes: [NSAttributedString.Key: Any] = [
                    .font: font(size: size, bold: run.bold || forceBold, italic: run.italic || forceItalic, code: run.code),
                    .paragraphStyle: style,
                ]
                if let link = run.link, let url = URL(string: link) { attributes[.link] = url }
                output.append(NSAttributedString(string: run.text, attributes: attributes))
            }
            output.append(NSAttributedString(string: "\n", attributes: [.paragraphStyle: style]))
        }

        for block in document.blocks {
            switch block {
            case .heading(let level, let runs):
                let style = NSMutableParagraphStyle()
                style.paragraphSpacingBefore = 10
                style.paragraphSpacing = 6
                append(runs, size: [24, 20, 17, 15, 13, 12][min(level, 6) - 1], forceBold: true, style: style)
            case .paragraph(let runs):
                append(runs)
            case .quote(let runs):
                let style = NSMutableParagraphStyle()
                style.firstLineHeadIndent = 24
                style.headIndent = 24
                style.paragraphSpacing = 8
                append(runs, italic: true, style: style)
            case .listItem(let ordered, let number, let level, let runs):
                let style = NSMutableParagraphStyle()
                style.firstLineHeadIndent = CGFloat(level) * 18 + 6
                style.headIndent = CGFloat(level) * 18 + 24
                style.paragraphSpacing = 3
                append(runs, style: style, prefix: ordered ? "\(number). " : "•  ")
            case .code(let text):
                append([TextRun(text: text, code: true)], size: 11)
            case .table(let rows):
                for (index, row) in rows.enumerated() {
                    append([TextRun(text: row.joined(separator: "\t"), bold: index == 0)])
                }
            case .rule:
                append([TextRun(text: "————————————")])
            case .pageBreak:
                output.append(NSAttributedString(string: "\u{0C}"))
            }
        }
        return try output.data(from: NSRange(location: 0, length: output.length),
                               documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
    }
}

/// Comma-separated values. Output starts with a UTF-8 BOM so Excel shows ç, ğ, ş… correctly.
enum CSV {
    static func parse(_ text: String, delimiter: Character? = nil) -> [[String]] {
        let source = text.hasPrefix("\u{FEFF}") ? String(text.dropFirst()) : text
        let separator = delimiter ?? detectDelimiter(source)
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var chars = Array(source)
        if chars.last != "\n" { chars.append("\n") }
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if inQuotes {
                if c == "\"" {
                    if i + 1 < chars.count, chars[i + 1] == "\"" { field.append("\""); i += 1 } else { inQuotes = false }
                } else {
                    field.append(c)
                }
            } else if c == "\"" && field.isEmpty {
                inQuotes = true
            } else if c == separator {
                row.append(field)
                field = ""
            } else if c == "\n" || c == "\r\n" || c == "\r" {
                row.append(field)
                field = ""
                if !(row.count == 1 && row[0].isEmpty) { rows.append(row) }
                row = []
            } else {
                field.append(c)
            }
            i += 1
        }
        let width = rows.map(\.count).max() ?? 0
        return rows.map { $0 + Array(repeating: "", count: width - $0.count) }
    }

    private static func detectDelimiter(_ text: String) -> Character {
        let firstLine = text.prefix { $0 != "\n" && $0 != "\r\n" }
        let candidates: [Character] = [",", ";", "\t", "|"]
        return candidates.max { a, b in firstLine.filter { $0 == a }.count < firstLine.filter { $0 == b }.count } ?? ","
    }

    static func write(_ rows: [[String]]) -> Data {
        let text = rows.map { row in
            row.map { field in
                let needsQuotes = field.contains(",") || field.contains("\"") || field.contains("\n") || field.contains(";")
                    || field.hasPrefix(" ") || field.hasSuffix(" ")
                return needsQuotes ? "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : field
            }.joined(separator: ",")
        }.joined(separator: "\r\n")
        return Data(("\u{FEFF}" + text + "\r\n").utf8)
    }

    /// "12", "-3.5" → numbers; "007", "+90…", "1e5", long ids stay text.
    static func number(_ text: String) -> Double? {
        let value = text.trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty, value.count <= 15, value.allSatisfy({ "0123456789.-".contains($0) }),
              !(value.hasPrefix("0") && value.count > 1 && !value.hasPrefix("0.")),
              !(value.hasPrefix("-0") && value.count > 2 && !value.hasPrefix("-0.")),
              let number = Double(value), number.isFinite
        else { return nil }
        return number
    }
}

enum JSONTable {
    /// Arrays of objects (or arrays), possibly wrapped in an object, become a table.
    static func table(from data: Data) -> [[String]]? {
        guard let root = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else { return nil }
        var array = root as? [Any]
        if array == nil, let object = root as? [String: Any] {
            array = object.values.compactMap { $0 as? [Any] }.max { $0.count < $1.count }
        }
        guard let items = array, !items.isEmpty else { return nil }

        if let objects = items as? [[String: Any]] {
            let raw = String(decoding: data, as: UTF8.self)
            var keys: [String] = []
            for object in objects { for key in object.keys where !keys.contains(key) { keys.append(key) } }
            // Keep the column order of the file: sort by where each key first appears.
            func position(_ key: String) -> Int {
                guard let range = raw.range(of: "\"\(key)\"") else { return Int.max }
                return raw.distance(from: raw.startIndex, to: range.lowerBound)
            }
            keys.sort { position($0) < position($1) }
            return [keys] + objects.map { object in keys.map { string(object[$0]) } }
        }
        if let arrays = items as? [[Any]] {
            let rows = arrays.map { $0.map { string($0) } }
            let width = rows.map(\.count).max() ?? 0
            return rows.map { $0 + Array(repeating: "", count: width - $0.count) }
        }
        return [["value"]] + items.map { [string($0)] }
    }

    private static func string(_ value: Any?) -> String {
        switch value {
        case nil, is NSNull: return ""
        case let text as String: return text
        case let number as NSNumber:
            if CFGetTypeID(number) == CFBooleanGetTypeID() { return number.boolValue ? "true" : "false" }
            return number.stringValue
        case let other?:
            guard JSONSerialization.isValidJSONObject(other),
                  let data = try? JSONSerialization.data(withJSONObject: other, options: [.sortedKeys])
            else { return "\(other)" }
            return String(decoding: data, as: UTF8.self)
        }
    }

    static func prettyPrinted(_ data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]),
              let pretty = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .fragmentsAllowed, .withoutEscapingSlashes])
        else { return nil }
        return String(decoding: pretty, as: UTF8.self)
    }

    /// The header row becomes the keys, in order. Numbers and true/false keep their JSON types.
    static func json(from rows: [[String]]) -> Data {
        guard let header = rows.first else { return Data("[]".utf8) }
        let keys = header.enumerated().map { $1.isEmpty ? "column\($0 + 1)" : $1 }
        func fragment(_ value: Any) -> String {
            (try? JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed, .withoutEscapingSlashes]))
                .map { String(decoding: $0, as: UTF8.self) } ?? "\"\""
        }
        let objects = rows.dropFirst().map { row -> String in
            let fields = keys.enumerated().map { index, key -> String in
                let cell = index < row.count ? row[index] : ""
                let value: Any
                if cell == "true" {
                    value = true
                } else if cell == "false" {
                    value = false
                } else if let number = CSV.number(cell) {
                    value = number.rounded() == number && abs(number) < 1e15 ? Int(number) : number
                } else {
                    value = cell
                }
                return "    \(fragment(key)): \(fragment(value))"
            }
            return "  {\n" + fields.joined(separator: ",\n") + "\n  }"
        }
        return Data(("[\n" + objects.joined(separator: ",\n") + "\n]\n").utf8)
    }
}

/// Minimal .xlsx writer: one worksheet per table, inline strings, real numbers.
enum XlsxWriter {
    static func workbook(_ sheets: [(name: String, rows: [[String]])]) -> Data {
        var names: [String] = []
        for (index, sheet) in sheets.enumerated() {
            var name = String(sheet.name.filter { !"[]:*?/\\".contains($0) }.prefix(31))
            if name.isEmpty || names.contains(name) { name = "Sheet\(index + 1)" }
            names.append(name)
        }
        let contentTypes = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>\(sheets.indices.map { "<Override PartName=\"/xl/worksheets/sheet\($0 + 1).xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml\"/>" }.joined())</Types>
        """
        let rels = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>
        """
        let workbook = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets>\(names.enumerated().map { "<sheet name=\"\(xml($1))\" sheetId=\"\($0 + 1)\" r:id=\"rId\($0 + 1)\"/>" }.joined())</sheets></workbook>
        """
        let workbookRels = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">\(sheets.indices.map { "<Relationship Id=\"rId\($0 + 1)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet\" Target=\"worksheets/sheet\($0 + 1).xml\"/>" }.joined())</Relationships>
        """
        var zip = ZipWriter()
        zip.add(path: "[Content_Types].xml", data: Data(contentTypes.utf8))
        zip.add(path: "_rels/.rels", data: Data(rels.utf8))
        zip.add(path: "xl/workbook.xml", data: Data(workbook.utf8))
        zip.add(path: "xl/_rels/workbook.xml.rels", data: Data(workbookRels.utf8))
        for (index, sheet) in sheets.enumerated() {
            zip.add(path: "xl/worksheets/sheet\(index + 1).xml", data: Data(worksheet(sheet.rows).utf8))
        }
        return zip.finish()
    }

    private static func worksheet(_ rows: [[String]]) -> String {
        let body = rows.enumerated().map { r, row -> String in
            let cells = row.enumerated().compactMap { c, value -> String? in
                guard !value.isEmpty else { return nil }
                let ref = column(c) + "\(r + 1)"
                if r > 0, let number = CSV.number(value) {
                    return "<c r=\"\(ref)\"><v>\(number.rounded() == number && abs(number) < 1e15 ? String(Int(number)) : String(number))</v></c>"
                }
                return "<c r=\"\(ref)\" t=\"inlineStr\"><is><t xml:space=\"preserve\">\(xml(value))</t></is></c>"
            }.joined()
            return "<row r=\"\(r + 1)\">\(cells)</row>"
        }.joined()
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>\(body)</sheetData></worksheet>
        """
    }

    static func column(_ index: Int) -> String {
        var n = index + 1
        var name = ""
        while n > 0 {
            let r = (n - 1) % 26
            name = String(UnicodeScalar(65 + r)!) + name
            n = (n - 1) / 26
        }
        return name
    }

    static func xml(_ text: String) -> String {
        DocxWriter.escape(text)
    }
}

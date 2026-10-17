import Foundation

enum Markdown {

    // MARK: Parsing

    static func parse(_ source: String, title: String) -> RichDocument {
        let lines = source.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var blocks: [DocBlock] = []
        var paragraph: [String] = []

        func flush() {
            if !paragraph.isEmpty {
                blocks.append(.paragraph(inline(paragraph.joined(separator: " "))))
                paragraph = []
            }
        }

        var i = 0
        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                flush()
                let fence = String(trimmed.prefix(3))
                var code: [String] = []
                i += 1
                while i < lines.count, !lines[i].trimmingCharacters(in: .whitespaces).hasPrefix(fence) {
                    code.append(lines[i])
                    i += 1
                }
                blocks.append(.code(code.joined(separator: "\n")))
                i += 1
                continue
            }
            if trimmed.isEmpty {
                flush()
                i += 1
                continue
            }
            if let (level, text) = heading(trimmed) {
                flush()
                blocks.append(.heading(level: level, runs: inline(text)))
                i += 1
                continue
            }
            if isRule(trimmed) {
                flush()
                blocks.append(.rule)
                i += 1
                continue
            }
            if trimmed.contains("|"), i + 1 < lines.count, isTableSeparator(lines[i + 1]) {
                flush()
                var rows = [cells(trimmed)]
                i += 2
                while i < lines.count {
                    let next = lines[i].trimmingCharacters(in: .whitespaces)
                    guard !next.isEmpty, next.contains("|") else { break }
                    rows.append(cells(next))
                    i += 1
                }
                let width = rows.map(\.count).max() ?? 0
                blocks.append(.table(rows.map { $0 + Array(repeating: "", count: width - $0.count) }))
                continue
            }
            if trimmed.hasPrefix(">") {
                flush()
                var quote: [String] = []
                while i < lines.count {
                    let next = lines[i].trimmingCharacters(in: .whitespaces)
                    guard next.hasPrefix(">") else { break }
                    quote.append(String(next.dropFirst()).trimmingCharacters(in: .whitespaces))
                    i += 1
                }
                blocks.append(.quote(inline(quote.joined(separator: " "))))
                continue
            }
            if let item = listItem(line) {
                flush()
                blocks.append(item)
                i += 1
                continue
            }
            paragraph.append(trimmed)
            i += 1
        }
        flush()
        return RichDocument(title: title, blocks: blocks)
    }

    private static func heading(_ line: String) -> (Int, String)? {
        let hashes = line.prefix { $0 == "#" }.count
        guard (1...6).contains(hashes) else { return nil }
        let rest = line.dropFirst(hashes)
        guard rest.first == " " || rest.isEmpty else { return nil }
        var text = rest.trimmingCharacters(in: .whitespaces)
        while text.hasSuffix("#") { text.removeLast() }
        return (hashes, text.trimmingCharacters(in: .whitespaces))
    }

    private static func isRule(_ line: String) -> Bool {
        let compact = line.replacingOccurrences(of: " ", with: "")
        guard compact.count >= 3, let first = compact.first, "-*_".contains(first) else { return false }
        return compact.allSatisfy { $0 == first }
    }

    private static func isTableSeparator(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.contains("-") && trimmed.contains("|") && trimmed.allSatisfy { "|:- ".contains($0) }
    }

    private static func cells(_ line: String) -> [String] {
        var row = line.trimmingCharacters(in: .whitespaces)
        if row.hasPrefix("|") { row.removeFirst() }
        if row.hasSuffix("|") { row.removeLast() }
        return row.replacingOccurrences(of: "\\|", with: "\u{1}")
            .components(separatedBy: "|")
            .map { $0.replacingOccurrences(of: "\u{1}", with: "|").trimmingCharacters(in: .whitespaces) }
            .map { inline($0).plain }
    }

    private static func listItem(_ line: String) -> DocBlock? {
        let indent = line.prefix { $0 == " " || $0 == "\t" }
            .reduce(0) { $0 + ($1 == "\t" ? 4 : 1) }
        let rest = line.drop { $0 == " " || $0 == "\t" }
        let level = min(indent / 2, 5)
        if let marker = rest.first, "-*+".contains(marker), rest.dropFirst().first == " " {
            var text = String(rest.dropFirst(2))
            if text.hasPrefix("[ ] ") { text = "☐ " + text.dropFirst(4) }
            if text.lowercased().hasPrefix("[x] ") { text = "☑ " + text.dropFirst(4) }
            return .listItem(ordered: false, number: 0, level: level, runs: inline(text))
        }
        let digits = rest.prefix { $0.isNumber }
        if !digits.isEmpty, digits.count <= 9 {
            let after = rest.dropFirst(digits.count)
            if let marker = after.first, marker == "." || marker == ")", after.dropFirst().first == " " {
                return .listItem(ordered: true, number: Int(digits) ?? 1, level: level,
                                 runs: inline(String(after.dropFirst(2))))
            }
        }
        return nil
    }

    /// **bold**, *italic*, `code`, [links](url), ![images](src), ~~strike~~, \escapes.
    static func inline(_ text: String) -> [TextRun] {
        var runs: [TextRun] = []
        var current = ""
        var bold = false
        var italic = false
        let chars = Array(text)

        func emit() {
            if !current.isEmpty {
                runs.append(TextRun(text: current, bold: bold, italic: italic))
                current = ""
            }
        }
        func isWord(_ index: Int) -> Bool {
            index >= 0 && index < chars.count && (chars[index].isLetter || chars[index].isNumber)
        }
        func isSpace(_ index: Int) -> Bool {
            index < 0 || index >= chars.count || chars[index].isWhitespace
        }

        var i = 0
        while i < chars.count {
            let c = chars[i]
            if c == "\\", i + 1 < chars.count, "\\`*_{}[]()#+-.!|~".contains(chars[i + 1]) {
                current.append(chars[i + 1])
                i += 2
                continue
            }
            if c == "`", let end = chars[(i + 1)...].firstIndex(of: "`") {
                emit()
                runs.append(TextRun(text: String(chars[(i + 1)..<end]), bold: bold, italic: italic, code: true))
                i = end + 1
                continue
            }
            if c == "~", i + 1 < chars.count, chars[i + 1] == "~" {
                i += 2
                continue
            }
            let isImage = c == "!" && i + 1 < chars.count && chars[i + 1] == "["
            if c == "[" || isImage {
                let open = isImage ? i + 1 : i
                if let close = chars[(open + 1)...].firstIndex(of: "]"), close + 1 < chars.count, chars[close + 1] == "(",
                   let end = chars[(close + 2)...].firstIndex(of: ")") {
                    emit()
                    let label = String(chars[(open + 1)..<close])
                    let target = String(chars[(close + 2)..<end]).split(separator: " ").first.map(String.init) ?? ""
                    if isImage {
                        if !label.isEmpty { runs.append(TextRun(text: label, bold: bold, italic: true)) }
                    } else {
                        runs.append(TextRun(text: label.isEmpty ? target : label, bold: bold, italic: italic, link: target))
                    }
                    i = end + 1
                    continue
                }
            }
            if c == "<", let end = chars[(i + 1)...].firstIndex(of: ">") {
                let inner = String(chars[(i + 1)..<end])
                if inner.hasPrefix("http://") || inner.hasPrefix("https://") || inner.hasPrefix("mailto:") {
                    emit()
                    runs.append(TextRun(text: inner, bold: bold, italic: italic, link: inner))
                    i = end + 1
                    continue
                }
            }
            if c == "*" || c == "_" {
                let double = i + 1 < chars.count && chars[i + 1] == c
                let width = double ? 2 : 1
                let before = i - 1, after = i + width
                // snake_case and "2 * 3" stay literal.
                let literal = (c == "_" && isWord(before) && isWord(after)) || (isSpace(before) && isSpace(after))
                if !literal {
                    emit()
                    if double { bold.toggle() } else { italic.toggle() }
                    i += width
                    continue
                }
            }
            current.append(c)
            i += 1
        }
        emit()
        return runs
    }

    // MARK: Writing

    static func write(_ document: RichDocument) -> String {
        var out: [String] = []
        var previousWasList = false
        for block in document.blocks {
            var isList = false
            switch block {
            case .heading(let level, let runs):
                out.append(String(repeating: "#", count: level) + " " + inlineMarkdown(runs))
            case .paragraph(let runs):
                out.append(inlineMarkdown(runs))
            case .listItem(let ordered, let number, let level, let runs):
                let item = String(repeating: "  ", count: level) + (ordered ? "\(number). " : "- ") + inlineMarkdown(runs)
                if previousWasList, let last = out.popLast() { out.append(last + "\n" + item) } else { out.append(item) }
                isList = true
            case .quote(let runs):
                out.append("> " + inlineMarkdown(runs))
            case .code(let text):
                out.append("```\n" + text + "\n```")
            case .table(let rows):
                guard let header = rows.first else { continue }
                let escape = { (cell: String) in cell.replacingOccurrences(of: "|", with: "\\|").replacingOccurrences(of: "\n", with: " ") }
                var lines = ["| " + header.map(escape).joined(separator: " | ") + " |",
                             "|" + header.map { _ in " --- " }.joined(separator: "|") + "|"]
                lines += rows.dropFirst().map { "| " + $0.map(escape).joined(separator: " | ") + " |" }
                out.append(lines.joined(separator: "\n"))
            case .rule, .pageBreak:
                out.append("---")
            }
            previousWasList = isList
        }
        return out.joined(separator: "\n\n") + "\n"
    }

    private static func inlineMarkdown(_ runs: [TextRun]) -> String {
        runs.map { run in
            var text = run.code ? "`\(run.text)`" : run.text
            if let link = run.link { text = "[\(text)](\(link))" }
            if run.italic { text = "*\(text)*" }
            if run.bold { text = "**\(text)**" }
            return text
        }.joined()
    }
}

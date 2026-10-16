import Compression
import Foundation

/// Builds a valid .docx (Office Open XML) with headings, bold/italic, lists, quotes, code and tables.
enum DocxWriter {
    /// Plain paragraphs, one page per entry (used by PDF to Word).
    static func document(pages: [[String]]) -> Data {
        var blocks: [DocBlock] = []
        for (index, paragraphs) in pages.enumerated() {
            if index > 0 { blocks.append(.pageBreak) }
            blocks += paragraphs.map { .paragraph([TextRun(text: $0)]) }
        }
        return document(RichDocument(title: "", blocks: blocks))
    }

    static func document(_ document: RichDocument) -> Data {
        var body = ""
        for block in document.blocks {
            switch block {
            case .heading(let level, let runs):
                let size = [32, 26, 22, 18, 16, 14][min(level, 6) - 1] * 2
                body += paragraph(runs, properties: "<w:spacing w:before=\"240\" w:after=\"120\"/><w:outlineLvl w:val=\"\(level - 1)\"/>",
                                  bold: true, size: size, color: level <= 2 ? "1F3864" : nil)
            case .paragraph(let runs):
                body += paragraph(runs, properties: "<w:spacing w:after=\"120\"/>")
            case .listItem(let ordered, let number, let level, let runs):
                let indent = 360 + level * 360
                body += paragraph([TextRun(text: ordered ? "\(number).\t" : "•\t")] + runs,
                                  properties: "<w:tabs><w:tab w:val=\"left\" w:pos=\"\(indent)\"/></w:tabs><w:spacing w:after=\"60\"/><w:ind w:left=\"\(indent)\" w:hanging=\"360\"/>")
            case .quote(let runs):
                body += paragraph(runs, properties: "<w:pBdr><w:left w:val=\"single\" w:sz=\"18\" w:space=\"8\" w:color=\"BFBFBF\"/></w:pBdr><w:spacing w:after=\"120\"/><w:ind w:left=\"360\"/>",
                                  italic: true, color: "595959")
            case .code(let text):
                for line in text.components(separatedBy: "\n") {
                    body += paragraph([TextRun(text: line, code: true)],
                                      properties: "<w:shd w:val=\"clear\" w:color=\"auto\" w:fill=\"F2F2F2\"/><w:spacing w:after=\"0\"/>",
                                      size: 19)
                }
                body += "<w:p/>"
            case .table(let rows):
                body += table(rows)
            case .rule:
                body += "<w:p><w:pPr><w:pBdr><w:bottom w:val=\"single\" w:sz=\"6\" w:space=\"1\" w:color=\"BFBFBF\"/></w:pBdr></w:pPr></w:p>"
            case .pageBreak:
                body += #"<w:p><w:r><w:br w:type="page"/></w:r></w:p>"#
            }
        }
        let documentXML = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body>\(body)<w:sectPr><w:pgSz w:w="11906" w:h="16838"/><w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440" w:header="708" w:footer="708" w:gutter="0"/></w:sectPr></w:body></w:document>
        """
        let contentTypes = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/></Types>
        """
        let rels = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>
        """
        var zip = ZipWriter()
        zip.add(path: "[Content_Types].xml", data: Data(contentTypes.utf8))
        zip.add(path: "_rels/.rels", data: Data(rels.utf8))
        zip.add(path: "word/document.xml", data: Data(documentXML.utf8))
        return zip.finish()
    }

    private static func paragraph(_ runs: [TextRun], properties: String, bold: Bool = false, italic: Bool = false,
                                  size: Int? = nil, color: String? = nil) -> String {
        "<w:p><w:pPr>\(properties)</w:pPr>" + runs.map { run($0, bold: bold, italic: italic, size: size, color: color) }.joined() + "</w:p>"
    }

    /// rPr children must follow the schema order: rFonts, b, i, color, sz, u.
    private static func run(_ run: TextRun, bold: Bool = false, italic: Bool = false, size: Int? = nil, color: String? = nil) -> String {
        var properties = ""
        if run.code { properties += #"<w:rFonts w:ascii="Courier New" w:hAnsi="Courier New" w:cs="Courier New"/>"# }
        if run.bold || bold { properties += "<w:b/>" }
        if run.italic || italic { properties += "<w:i/>" }
        if let color = run.link != nil ? "0563C1" : color { properties += "<w:color w:val=\"\(color)\"/>" }
        if let size { properties += "<w:sz w:val=\"\(size)\"/>" }
        if run.link != nil { properties += #"<w:u w:val="single"/>"# }
        let rPr = properties.isEmpty ? "" : "<w:rPr>\(properties)</w:rPr>"
        // Tabs and line breaks inside a run need their own elements.
        let pieces = run.text.components(separatedBy: "\n").map { line in
            line.components(separatedBy: "\t").map { #"<w:t xml:space="preserve">"# + escape($0) + "</w:t>" }.joined(separator: "<w:tab/>")
        }.joined(separator: "<w:br/>")
        return "<w:r>\(rPr)\(pieces)</w:r>"
    }

    private static func table(_ rows: [[String]]) -> String {
        guard let width = rows.map(\.count).max(), width > 0 else { return "" }
        let border = #"w:val="single" w:sz="4" w:space="0" w:color="A6A6A6""#
        var xml = "<w:tbl><w:tblPr><w:tblW w:w=\"5000\" w:type=\"pct\"/><w:tblBorders><w:top \(border)/><w:left \(border)/><w:bottom \(border)/><w:right \(border)/><w:insideH \(border)/><w:insideV \(border)/></w:tblBorders></w:tblPr><w:tblGrid>"
        xml += String(repeating: "<w:gridCol w:w=\"\(9026 / width)\"/>", count: width) + "</w:tblGrid>"
        for (index, row) in rows.enumerated() {
            xml += "<w:tr>"
            for column in 0..<width {
                let text = column < row.count ? row[column] : ""
                let shade = index == 0 ? #"<w:shd w:val="clear" w:color="auto" w:fill="F2F2F2"/>"# : ""
                xml += "<w:tc><w:tcPr><w:tcW w:w=\"\(9026 / width)\" w:type=\"dxa\"/>\(shade)</w:tcPr>"
                xml += "<w:p>" + run(TextRun(text: text), bold: index == 0) + "</w:p></w:tc>"
            }
            xml += "</w:tr>"
        }
        return xml + "</w:tbl><w:p/>"
    }

    static func escape(_ text: String) -> String {
        // Drop control characters that are invalid in XML 1.0.
        let filtered = text.unicodeScalars.filter { scalar in
            scalar.value == 0x9 || scalar.value == 0xA || scalar.value == 0xD || scalar.value >= 0x20
        }
        return String(String.UnicodeScalarView(filtered))
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}

/// ZIP writer with DEFLATE compression (falls back to storing when that is not smaller).
struct ZipWriter {
    private var archive = Data()
    private var directory = Data()
    private var entries: UInt16 = 0

    mutating func add(path: String, data: Data) {
        let name = Data(path.utf8)
        let crc = CRC32.checksum(data)
        let offset = UInt32(archive.count)
        let deflated = Self.deflate(data)
        let (method, payload): (UInt16, Data) = deflated.map { $0.count < data.count ? (8, $0) : (0, data) } ?? (0, data)
        let dosDate: UInt16 = (46 << 9) | (1 << 5) | 1 // 2026-01-01

        archive.appendLE(UInt32(0x04034b50))
        archive.appendLE(UInt16(20)); archive.appendLE(UInt16(0)); archive.appendLE(method)
        archive.appendLE(UInt16(0)); archive.appendLE(dosDate)
        archive.appendLE(crc); archive.appendLE(UInt32(payload.count)); archive.appendLE(UInt32(data.count))
        archive.appendLE(UInt16(name.count)); archive.appendLE(UInt16(0))
        archive.append(name)
        archive.append(payload)

        directory.appendLE(UInt32(0x02014b50))
        directory.appendLE(UInt16(20)); directory.appendLE(UInt16(20))
        directory.appendLE(UInt16(0)); directory.appendLE(method)
        directory.appendLE(UInt16(0)); directory.appendLE(dosDate)
        directory.appendLE(crc); directory.appendLE(UInt32(payload.count)); directory.appendLE(UInt32(data.count))
        directory.appendLE(UInt16(name.count)); directory.appendLE(UInt16(0)); directory.appendLE(UInt16(0))
        directory.appendLE(UInt16(0)); directory.appendLE(UInt16(0)); directory.appendLE(UInt32(0))
        directory.appendLE(offset)
        directory.append(name)
        entries += 1
    }

    func finish() -> Data {
        var output = archive
        output.append(directory)
        output.appendLE(UInt32(0x06054b50))
        output.appendLE(UInt16(0)); output.appendLE(UInt16(0))
        output.appendLE(entries); output.appendLE(entries)
        output.appendLE(UInt32(directory.count)); output.appendLE(UInt32(archive.count))
        output.appendLE(UInt16(0))
        return output
    }

    /// Raw DEFLATE (what ZIP method 8 expects); COMPRESSION_ZLIB is raw deflate without a zlib header.
    static func deflate(_ data: Data) -> Data? {
        guard !data.isEmpty else { return nil }
        var output = [UInt8](repeating: 0, count: data.count + 1024)
        let count = data.withUnsafeBytes { source -> Int in
            compression_encode_buffer(&output, output.count, source.bindMemory(to: UInt8.self).baseAddress!, data.count,
                                      nil, COMPRESSION_ZLIB)
        }
        return count > 0 ? Data(output.prefix(count)) : nil
    }
}

/// Reads ZIP archives (stored and DEFLATE entries) — .docx, .xlsx, .pptx are ZIPs.
struct ZipReader {
    let entries: [String: Data]

    init(data: Data) throws {
        let bytes = [UInt8](data)
        func u16(_ o: Int) throws -> Int {
            guard o >= 0, o + 2 <= bytes.count else { throw PDFToolError.message("The file is damaged.") }
            return Int(bytes[o]) | Int(bytes[o + 1]) << 8
        }
        func u32(_ o: Int) throws -> Int {
            guard o >= 0, o + 4 <= bytes.count else { throw PDFToolError.message("The file is damaged.") }
            return Int(bytes[o]) | Int(bytes[o + 1]) << 8 | Int(bytes[o + 2]) << 16 | Int(bytes[o + 3]) << 24
        }
        var eocd = bytes.count - 22
        let lowest = max(0, bytes.count - 22 - 65_535)
        while eocd >= lowest, (try? u32(eocd)) != 0x06054b50 { eocd -= 1 }
        guard eocd >= lowest else { throw PDFToolError.message("This is not a valid Office file.") }

        var result: [String: Data] = [:]
        var cd = try u32(eocd + 16)
        let count = try u16(eocd + 10)
        for _ in 0..<count {
            guard try u32(cd) == 0x02014b50 else { break }
            let method = try u16(cd + 10)
            let compressedSize = try u32(cd + 20), size = try u32(cd + 24)
            let nameLength = try u16(cd + 28), extra = try u16(cd + 30), comment = try u16(cd + 32)
            let local = try u32(cd + 42)
            guard cd + 46 + nameLength <= bytes.count else { break }
            let name = String(decoding: bytes[(cd + 46)..<(cd + 46 + nameLength)], as: UTF8.self)
            let localName = try u16(local + 26)
            let localExtra = try u16(local + 28)
            let start = local + 30 + localName + localExtra
            if start + compressedSize <= bytes.count {
                let payload = Data(bytes[start..<(start + compressedSize)])
                if method == 0 {
                    result[name] = payload
                } else if method == 8, let inflated = Self.inflate(payload, size: size) {
                    result[name] = inflated
                }
            }
            cd += 46 + nameLength + extra + comment
        }
        entries = result
    }

    static func inflate(_ data: Data, size: Int) -> Data? {
        guard size > 0 else { return Data() }
        guard !data.isEmpty else { return nil }
        var output = [UInt8](repeating: 0, count: size)
        let count = data.withUnsafeBytes { source -> Int in
            compression_decode_buffer(&output, size, source.bindMemory(to: UInt8.self).baseAddress!, data.count,
                                      nil, COMPRESSION_ZLIB)
        }
        return count > 0 ? Data(output.prefix(count)) : nil
    }
}

enum CRC32 {
    private static let table: [UInt32] = (0..<256).map { value in
        var c = UInt32(value)
        for _ in 0..<8 { c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1 }
        return c
    }

    static func checksum(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for byte in data { crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8) }
        return crc ^ 0xFFFFFFFF
    }
}

private extension Data {
    mutating func appendLE<T: FixedWidthInteger>(_ value: T) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }
}

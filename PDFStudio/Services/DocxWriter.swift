import Foundation

/// Builds a minimal, valid .docx (Office Open XML) document from plain paragraphs.
enum DocxWriter {
    static func document(pages: [[String]]) -> Data {
        var body = ""
        for (index, paragraphs) in pages.enumerated() {
            if index > 0 { body += #"<w:p><w:r><w:br w:type="page"/></w:r></w:p>"# }
            for paragraph in paragraphs {
                body += #"<w:p><w:r><w:t xml:space="preserve">"# + escape(paragraph) + "</w:t></w:r></w:p>"
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

    private static func escape(_ text: String) -> String {
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

/// Tiny ZIP writer (stored entries, no compression) – enough for .docx packages.
struct ZipWriter {
    private var archive = Data()
    private var directory = Data()
    private var entries: UInt16 = 0

    mutating func add(path: String, data: Data) {
        let name = Data(path.utf8)
        let crc = CRC32.checksum(data)
        let offset = UInt32(archive.count)
        let size = UInt32(data.count)
        let dosDate: UInt16 = (46 << 9) | (1 << 5) | 1 // 2026-01-01

        archive.appendLE(UInt32(0x04034b50))
        archive.appendLE(UInt16(20)); archive.appendLE(UInt16(0)); archive.appendLE(UInt16(0))
        archive.appendLE(UInt16(0)); archive.appendLE(dosDate)
        archive.appendLE(crc); archive.appendLE(size); archive.appendLE(size)
        archive.appendLE(UInt16(name.count)); archive.appendLE(UInt16(0))
        archive.append(name)
        archive.append(data)

        directory.appendLE(UInt32(0x02014b50))
        directory.appendLE(UInt16(20)); directory.appendLE(UInt16(20))
        directory.appendLE(UInt16(0)); directory.appendLE(UInt16(0))
        directory.appendLE(UInt16(0)); directory.appendLE(dosDate)
        directory.appendLE(crc); directory.appendLE(size); directory.appendLE(size)
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

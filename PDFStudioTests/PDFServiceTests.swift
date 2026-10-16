import PDFKit
import XCTest
@testable import PDFStudio

final class PDFServiceTests: XCTestCase {

    // MARK: Helpers

    /// A PDF whose pages carry selectable text "Page N <tag>" and a black square in the top-left corner.
    private func makePDF(pages: Int, tag: String = "Sample", size: CGSize = CGSize(width: 595, height: 842)) -> PDFDocument {
        let data = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: size)).pdfData { ctx in
            for page in 1...pages {
                ctx.beginPage()
                UIColor.black.setFill()
                ctx.fill(CGRect(x: 0, y: 0, width: 120, height: 120))
                ("Page \(page) \(tag)" as NSString).draw(at: CGPoint(x: 150, y: 300),
                                                         withAttributes: [.font: UIFont.systemFont(ofSize: 24)])
            }
        }
        return PDFDocument(data: data)!
    }

    private func pageTexts(_ data: Data) -> [String] {
        guard let doc = PDFDocument(data: data) else { return [] }
        return (0..<doc.pageCount).map { doc.page(at: $0)?.string ?? "" }
    }

    /// Fraction of dark pixels inside a normalized region of an image.
    private func darkness(_ image: UIImage, in region: CGRect) -> Double {
        let cg = image.cgImage!
        let width = cg.width, height = cg.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let ctx = CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
        var dark = 0, total = 0
        let x0 = Int(region.minX * CGFloat(width)), x1 = Int(region.maxX * CGFloat(width))
        let y0 = Int(region.minY * CGFloat(height)), y1 = Int(region.maxY * CGFloat(height))
        for y in y0..<y1 {
            for x in x0..<x1 {
                let i = (y * width + x) * 4
                if pixels[i] < 60 && pixels[i + 1] < 60 && pixels[i + 2] < 60 { dark += 1 }
                total += 1
            }
        }
        return Double(dark) / Double(max(total, 1))
    }

    // MARK: Organize

    func testParseRanges() throws {
        XCTAssertEqual(try PDFService.parseRanges("1-3, 5, 8-", pageCount: 10), [[0, 1, 2], [4], [7, 8, 9]])
        XCTAssertEqual(try PDFService.parseRanges("2;4", pageCount: 4), [[1], [3]])
        for bad in ["", "0-2", "5-3", "abc", "1-11", "1--2"] {
            XCTAssertThrowsError(try PDFService.parseRanges(bad, pageCount: 10), "\"\(bad)\" should be rejected")
        }
    }

    func testMergeAndCopyPages() throws {
        let merged = PDFService.merge([makePDF(pages: 3, tag: "A"), makePDF(pages: 2, tag: "B")])
        XCTAssertEqual(merged.pageCount, 5)
        let texts = pageTexts(try PDFService.data(of: merged))
        XCTAssertTrue(texts[0].contains("Page 1 A"))
        XCTAssertTrue(texts[4].contains("Page 2 B"))

        let picked = PDFService.copyPages(makePDF(pages: 4), indices: [3, 0])
        let pickedTexts = pageTexts(try PDFService.data(of: picked))
        XCTAssertEqual(pickedTexts.count, 2)
        XCTAssertTrue(pickedTexts[0].contains("Page 4"))
        XCTAssertTrue(pickedTexts[1].contains("Page 1"))
    }

    func testRotateSurvivesSaving() throws {
        let doc = makePDF(pages: 2)
        PDFService.rotate(doc, by: 90)
        PDFService.rotate(doc, by: 270, pages: [1])
        let reopened = PDFDocument(data: try PDFService.data(of: doc))!
        XCTAssertEqual(reopened.page(at: 0)?.rotation, 90)
        XCTAssertEqual(reopened.page(at: 1)?.rotation, 0)
        XCTAssertEqual(PDFService.displaySize(reopened.page(at: 0)!), CGSize(width: 842, height: 595))
    }

    // MARK: Rendering

    func testRenderKeepsOrientation() {
        let doc = makePDF(pages: 1)
        let page = doc.page(at: 0)!
        let upright = PDFService.renderImage(page, scale: 0.5)
        XCTAssertEqual(upright.size, CGSize(width: 595, height: 842))
        XCTAssertGreaterThan(darkness(upright, in: CGRect(x: 0, y: 0, width: 0.15, height: 0.1)), 0.8, "square should be top-left")
        XCTAssertLessThan(darkness(upright, in: CGRect(x: 0, y: 0.85, width: 0.15, height: 0.1)), 0.1, "page must not be upside down")

        // Rotated 90° clockwise, the top-left square moves to the top-right.
        page.rotation = 90
        let rotated = PDFService.renderImage(page, scale: 0.5)
        XCTAssertEqual(rotated.size, CGSize(width: 842, height: 595))
        XCTAssertGreaterThan(darkness(rotated, in: CGRect(x: 0.9, y: 0, width: 0.1, height: 0.15)), 0.8, "square should be top-right")
    }

    func testStampKeepsTextAndAddsWatermark() throws {
        let doc = makePDF(pages: 3)
        let data = PDFService.watermark(doc, text: "CONFIDENTIAL", fontSize: 40, color: .red, opacity: 0.3, layout: .diagonal)
        let texts = pageTexts(data)
        XCTAssertEqual(texts.count, 3)
        XCTAssertTrue(texts[2].contains("Page 3"), "original text must stay selectable")
        XCTAssertTrue(texts[2].contains("CONFIDENTIAL"))

        let tiled = PDFService.watermark(doc, text: "DRAFT", fontSize: 20, color: .gray, opacity: 0.2, layout: .tiled)
        XCTAssertEqual(PDFDocument(data: tiled)?.pageCount, 3)
    }

    func testStampOnRotatedPageKeepsDisplaySize() {
        let doc = makePDF(pages: 1)
        doc.page(at: 0)!.rotation = 90
        let out = PDFDocument(data: PDFService.watermark(doc, text: "X", fontSize: 20, color: .red, opacity: 1, layout: .horizontal))!
        XCTAssertEqual(PDFService.displaySize(out.page(at: 0)!), CGSize(width: 842, height: 595))
    }

    func testPageNumbers() {
        let data = PDFService.addPageNumbers(makePDF(pages: 3), position: .bottomRight, format: .pageOfTotal,
                                             startAt: 1, fontSize: 12, skipFirst: false)
        let texts = pageTexts(data)
        XCTAssertTrue(texts[0].contains("Page 1 of 3"))
        XCTAssertTrue(texts[2].contains("Page 3 of 3"))

        let skipped = pageTexts(PDFService.addPageNumbers(makePDF(pages: 3), position: .topCenter, format: .number,
                                                          startAt: 5, fontSize: 12, skipFirst: true))
        XCTAssertFalse(skipped[0].contains("5"))
        XCTAssertTrue(skipped[1].contains("5"))
        XCTAssertTrue(skipped[2].contains("6"))
    }

    // MARK: Optimize

    func testCompressMakesPhotoPDFSmaller() throws {
        // A noisy "photo" compresses badly, so the original is large.
        let size = CGSize(width: 1600, height: 1200)
        let photo = UIGraphicsImageRenderer(size: size).image { ctx in
            for _ in 0..<4000 {
                UIColor(hue: .random(in: 0...1), saturation: 0.8, brightness: .random(in: 0.3...1), alpha: 1).setFill()
                ctx.fill(CGRect(x: .random(in: 0...size.width), y: .random(in: 0...size.height), width: 30, height: 30))
            }
        }
        let original = PDFService.imagesToPDF([photo, photo], pageSize: .a4, margin: .none, quality: 1.0)
        let doc = PDFDocument(data: original)!
        var progress: [Int] = []
        let compressed = PDFService.compress(doc, level: .extreme) { current, _ in progress.append(current) }
        XCTAssertEqual(PDFDocument(data: compressed)?.pageCount, 2)
        XCTAssertLessThan(compressed.count, original.count)
        XCTAssertEqual(progress, [1, 2])
    }

    func testCrop() {
        let doc = makePDF(pages: 2)
        PDFService.crop(doc, top: 0.1, bottom: 0.2, left: 0.05, right: 0.05)
        let box = doc.page(at: 1)!.bounds(for: .cropBox)
        XCTAssertEqual(box.width, 595 * 0.9, accuracy: 0.5)
        XCTAssertEqual(box.height, 842 * 0.7, accuracy: 0.5)
        XCTAssertEqual(box.minY, 842 * 0.2, accuracy: 0.5)
    }

    func testImagesToPDFPageSizes() {
        let portrait = UIGraphicsImageRenderer(size: CGSize(width: 300, height: 400)).image { _ in }
        let landscape = UIGraphicsImageRenderer(size: CGSize(width: 400, height: 300)).image { _ in }
        let doc = PDFDocument(data: PDFService.imagesToPDF([portrait, landscape], pageSize: .a4, margin: .small))!
        XCTAssertEqual(doc.pageCount, 2)
        XCTAssertEqual(doc.page(at: 0)!.bounds(for: .mediaBox).size.width, 595.2, accuracy: 0.5)
        XCTAssertEqual(doc.page(at: 1)!.bounds(for: .mediaBox).size.width, 841.8, accuracy: 0.5)

        let fit = PDFDocument(data: PDFService.imagesToPDF([portrait], pageSize: .fit, margin: .none))!
        XCTAssertEqual(fit.page(at: 0)!.bounds(for: .mediaBox).size, CGSize(width: 300, height: 400))
    }

    // MARK: Security

    func testProtectAndUnlock() throws {
        let protected = try PDFService.protect(makePDF(pages: 2), password: "s3cret")
        let locked = PDFDocument(data: protected)!
        XCTAssertTrue(locked.isLocked)
        XCTAssertFalse(locked.unlock(withPassword: "wrong"))
        XCTAssertTrue(locked.unlock(withPassword: "s3cret"))

        let freed = PDFDocument(data: try PDFService.unlocked(locked))!
        XCTAssertFalse(freed.isEncrypted)
        XCTAssertFalse(freed.isLocked)
        XCTAssertEqual(freed.pageCount, 2)
        XCTAssertTrue((freed.page(at: 1)?.string ?? "").contains("Page 2"))
    }

    // MARK: Text, Word, OCR

    func testParagraphJoining() {
        let text = "This is a long line that wraps onto the next\nline of the same paragraph.\n\nShort title\nAnother hyphen-\nated word continues here and is long enough to wrap"
        let paragraphs = TextExtractor.paragraphs(text)
        XCTAssertEqual(paragraphs.first, "This is a long line that wraps onto the next line of the same paragraph.")
        XCTAssertTrue(paragraphs.contains("Short title"))
        XCTAssertTrue(paragraphs.contains { $0.contains("hyphenated") })
    }

    func testTextExtraction() throws {
        let pages = try TextExtractor.pages(of: makePDF(pages: 2, tag: "Hello"), useOCR: false) { _, _ in }
        XCTAssertEqual(pages.count, 2)
        XCTAssertTrue(pages[1].contains("Page 2 Hello"))
        let md = TextExtractor.markdown(title: "Doc", pages: pages)
        XCTAssertTrue(md.hasPrefix("# Doc"))
        XCTAssertTrue(md.contains("## Page 2"))
    }

    func testDocxIsValidZipWithWellFormedXML() throws {
        let docx = DocxWriter.document(pages: [["Hello & <World>", "Ünicode çğış"], ["Second page"]])
        let entries = try readStoredZip(docx)
        XCTAssertEqual(Set(entries.keys), ["[Content_Types].xml", "_rels/.rels", "word/document.xml"])
        for (name, data) in entries {
            let parser = XMLParser(data: data)
            XCTAssertTrue(parser.parse(), "\(name) is not well-formed XML: \(String(describing: parser.parserError))")
        }
        let xml = String(data: entries["word/document.xml"]!, encoding: .utf8)!
        XCTAssertTrue(xml.contains("Hello &amp; &lt;World&gt;"))
        XCTAssertTrue(xml.contains("Ünicode çğış"))
        XCTAssertTrue(xml.contains(#"w:type="page""#))
    }

    /// Reads a ZIP made of stored entries, verifying every CRC and the central directory.
    private func readStoredZip(_ data: Data) throws -> [String: Data] {
        let bytes = [UInt8](data)
        func u16(_ o: Int) -> Int { Int(bytes[o]) | Int(bytes[o + 1]) << 8 }
        func u32(_ o: Int) -> UInt32 { UInt32(bytes[o]) | UInt32(bytes[o + 1]) << 8 | UInt32(bytes[o + 2]) << 16 | UInt32(bytes[o + 3]) << 24 }
        let eocd = bytes.count - 22
        XCTAssertEqual(u32(eocd), 0x06054b50, "end of central directory")
        let count = u16(eocd + 10)
        var cd = Int(u32(eocd + 16))
        var result: [String: Data] = [:]
        for _ in 0..<count {
            XCTAssertEqual(u32(cd), 0x02014b50)
            let crc = u32(cd + 16), size = Int(u32(cd + 20))
            let nameLength = u16(cd + 28), extra = u16(cd + 30), comment = u16(cd + 32)
            let local = Int(u32(cd + 42))
            let name = String(bytes: bytes[(cd + 46)..<(cd + 46 + nameLength)], encoding: .utf8)!
            XCTAssertEqual(u32(local), 0x04034b50)
            let start = local + 30 + u16(local + 26) + u16(local + 28)
            let content = Data(bytes[start..<(start + size)])
            XCTAssertEqual(CRC32.checksum(content), crc, "CRC of \(name)")
            result[name] = content
            cd += 46 + nameLength + extra + comment
        }
        return result
    }

    func testCRC32KnownValue() {
        XCTAssertEqual(CRC32.checksum(Data("123456789".utf8)), 0xCBF43926)
    }

    func testOCRMakesScannedPageSearchable() throws {
        // A "scan": text rendered into an image, so the PDF has no text layer.
        let image = UIGraphicsImageRenderer(size: CGSize(width: 1240, height: 1754)).image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 1240, height: 1754))
            ("INVOICE TOTAL 4840" as NSString).draw(at: CGPoint(x: 120, y: 300),
                                                    withAttributes: [.font: UIFont.boldSystemFont(ofSize: 72)])
        }
        let scan = PDFDocument(data: PDFService.imagesToPDF([image], pageSize: .a4, margin: .none))!
        XCTAssertFalse(OCRService.hasText(scan.page(at: 0)!))

        let lines = try OCRService.recognize(image)
        XCTAssertTrue(OCRService.text(of: lines).uppercased().contains("INVOICE"), "OCR read: \(OCRService.text(of: lines))")

        let searchable = PDFDocument(data: try OCRService.searchablePDF(scan, skipPagesWithText: true) { _, _ in })!
        XCTAssertTrue((searchable.page(at: 0)?.string ?? "").uppercased().contains("INVOICE"))
        XCTAssertNotNil(searchable.findString("4840", withOptions: .caseInsensitive).first)

        let ocrText = try TextExtractor.pages(of: scan, useOCR: true) { _, _ in }
        XCTAssertTrue(ocrText[0].uppercased().contains("TOTAL"))
    }

    // MARK: Web / Office

    @MainActor
    func testHTMLToPDF() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("test-\(UUID().uuidString).html")
        let paragraphs = (1...80).map { "<p>Paragraph \($0) with some text to fill the page.</p>" }.joined()
        try "<html><body><h1>Quarterly Report</h1>\(paragraphs)</body></html>".write(to: url, atomically: true, encoding: .utf8)
        let data = try await WebPDFRenderer.pdf(fromFile: url, paper: .a4)
        let doc = try XCTUnwrap(PDFDocument(data: data))
        XCTAssertGreaterThan(doc.pageCount, 1, "long content should paginate")
        XCTAssertTrue((doc.page(at: 0)?.string ?? "").contains("Quarterly Report"))
        XCTAssertEqual(doc.page(at: 0)!.bounds(for: .mediaBox).width, 595.2, accuracy: 1)
    }

    // MARK: Files

    func testFileStoreUniqueNamesAndSanitizing() throws {
        let store = FileStore()
        let base = "UnitTest \(UUID().uuidString.prefix(6))"
        let first = try store.save(Data("a".utf8), baseName: base, ext: "txt")
        let second = try store.save(Data("b".utf8), baseName: base, ext: "txt")
        defer { try? FileManager.default.removeItem(at: first); try? FileManager.default.removeItem(at: second) }
        XCTAssertEqual(first.lastPathComponent, "\(base).txt")
        XCTAssertEqual(second.lastPathComponent, "\(base) (2).txt")
        XCTAssertTrue(store.files.contains { $0.url.lastPathComponent == second.lastPathComponent })
        XCTAssertEqual(FileStore.sanitize("a/b:c?"), "a-b-c-")
        XCTAssertEqual(FileStore.sanitize("   "), "Document")
    }
}

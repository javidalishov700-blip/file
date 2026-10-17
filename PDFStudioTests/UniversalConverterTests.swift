import AVFoundation
import ImageIO
import PDFKit
import XCTest
@testable import PDFStudio

final class UniversalConverterTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("conv-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    // MARK: Sample files

    private func write(_ data: Data, _ name: String) throws -> URL {
        let url = dir.appendingPathComponent(name)
        try data.write(to: url)
        return url
    }

    private func samplePDF(_ name: String = "doc.pdf", pages: Int = 2) throws -> URL {
        let data = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 595, height: 842)).pdfData { ctx in
            for page in 1...pages {
                ctx.beginPage()
                ("Hello converter page \(page)" as NSString).draw(at: CGPoint(x: 60, y: 80),
                                                                  withAttributes: [.font: UIFont.systemFont(ofSize: 22)])
            }
        }
        return try write(data, name)
    }

    /// A PNG with a transparent half.
    private func samplePNG(_ name: String = "pic.png") throws -> URL {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let image = UIGraphicsImageRenderer(size: CGSize(width: 200, height: 100), format: format).image { ctx in
            UIColor.red.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
        }
        return try write(image.pngData()!, name)
    }

    private func sampleWAV() throws -> URL {
        let url = dir.appendingPathComponent("tone.wav")
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
        let file = try AVAudioFile(forWriting: url, settings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 44_100, AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false,
        ])
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 44_100)!
        buffer.frameLength = 44_100
        for i in 0..<44_100 { buffer.floatChannelData![0][i] = sin(Float(i) * 2 * .pi * 440 / 44_100) * 0.5 }
        try file.write(from: buffer)
        return url
    }

    /// A 1-second, 10 fps H.264 movie with changing colors.
    private func sampleMovie() async throws -> URL {
        let url = dir.appendingPathComponent("clip.mov")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 320, AVVideoHeightKey: 240,
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
            kCVPixelBufferWidthKey as String: 320, kCVPixelBufferHeightKey as String: 240,
        ])
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)
        for frame in 0..<10 {
            while !input.isReadyForMoreMediaData { try await Task.sleep(nanoseconds: 10_000_000) }
            var pixelBuffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &pixelBuffer)
            let buffer = pixelBuffer!
            CVPixelBufferLockBaseAddress(buffer, [])
            let ctx = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: 320, height: 240, bitsPerComponent: 8,
                                bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue)!
            ctx.setFillColor(UIColor(hue: CGFloat(frame) / 10, saturation: 1, brightness: 1, alpha: 1).cgColor)
            ctx.fill(CGRect(x: 0, y: 0, width: 320, height: 240))
            CVPixelBufferUnlockBaseAddress(buffer, [])
            adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: 10))
        }
        input.markAsFinished()
        await writer.finishWriting()
        XCTAssertEqual(writer.status, .completed)
        return url
    }

    private func contents(_ output: OutputFile) throws -> Data {
        if let url = output.fileURL { return try Data(contentsOf: url) }
        return output.data
    }

    private func imageType(_ data: Data) -> String? {
        CGImageSourceCreateWithData(data as CFData, nil).flatMap { CGImageSourceGetType($0) as String? }
    }

    // MARK: Detection

    func testDetection() throws {
        XCTAssertEqual(UniversalConverter.detect(try samplePDF()), .pdf)
        XCTAssertEqual(UniversalConverter.detect(try samplePNG()), .image)
        XCTAssertEqual(UniversalConverter.detect(try write(Data("x".utf8), "a.docx")), .word)
        XCTAssertEqual(UniversalConverter.detect(try write(Data("x".utf8), "a.xlsx")), .spreadsheet)
        XCTAssertEqual(UniversalConverter.detect(try write(Data("x".utf8), "a.pptx")), .presentation)
        XCTAssertEqual(UniversalConverter.detect(try write(Data("x".utf8), "a.pages")), .office)
        XCTAssertEqual(UniversalConverter.detect(try write(Data("x".utf8), "a.txt")), .text)
        XCTAssertEqual(UniversalConverter.detect(try write(Data("x".utf8), "a.md")), .markdown)
        XCTAssertEqual(UniversalConverter.detect(try write(Data("x".utf8), "a.csv")), .table)
        XCTAssertEqual(UniversalConverter.detect(try write(Data("x".utf8), "a.json")), .json)
        XCTAssertEqual(UniversalConverter.detect(try write(Data("x".utf8), "a.svg")), .web)
        XCTAssertEqual(UniversalConverter.detect(try write(Data("x".utf8), "a.html")), .web)
        XCTAssertEqual(UniversalConverter.detect(try write(Data("x".utf8), "a.mp4")), .video)
        XCTAssertEqual(UniversalConverter.detect(try write(Data("x".utf8), "a.mp3")), .audio)
        // Wrong or missing extensions are detected from the content.
        let pdfData = try Data(contentsOf: try samplePDF())
        XCTAssertEqual(UniversalConverter.detect(try write(pdfData, "mystery")), .pdf)
        let pngData = try Data(contentsOf: try samplePNG())
        XCTAssertEqual(UniversalConverter.detect(try write(pngData, "photo.bin")), .image)
        XCTAssertEqual(UniversalConverter.detect(try write(Data([0, 1, 2, 3]), "blob.bin")), .unsupported)
    }

    func testTargetsExcludeOwnFormat() {
        XCTAssertFalse(UniversalConverter.targets(for: .image, ext: "jpeg").contains(.jpg))
        XCTAssertFalse(UniversalConverter.targets(for: .image, ext: "png").contains(.png))
        XCTAssertTrue(UniversalConverter.targets(for: .pdf).contains(.docx))
        XCTAssertTrue(UniversalConverter.targets(for: .unsupported).isEmpty)
    }

    // MARK: PDF →

    func testPDFToEverything() async throws {
        let url = try samplePDF(pages: 2)
        for target in UniversalConverter.targets(for: .pdf) {
            let outputs = try await UniversalConverter.convert(url, kind: .pdf, to: target)
            XCTAssertFalse(outputs.isEmpty, "\(target)")
            let data = try contents(outputs[0])
            XCTAssertGreaterThan(data.count, 20, "\(target)")
            XCTAssertEqual(outputs[0].ext, target.ext)
            switch target {
            case _ where target.imageType != nil:
                XCTAssertEqual(outputs.count, 2, "one image per page")
                XCTAssertNotNil(imageType(data), "\(target) should be a readable image")
            case .docx:
                XCTAssertEqual(data.prefix(2), Data("PK".utf8))
            default:
                let text = String(decoding: data, as: UTF8.self)
                XCTAssertTrue(text.contains("Hello converter page 2"), "\(target) lost the text")
            }
        }
    }

    // MARK: Image →

    func testImageToEverything() async throws {
        let url = try samplePNG()
        for target in UniversalConverter.targets(for: .image, ext: "png") where target != .txt && target != .docx && target != .md {
            let output = try await UniversalConverter.convert(url, kind: .image, to: target)[0]
            let data = try contents(output)
            if target == .pdf {
                XCTAssertEqual(PDFDocument(data: data)?.pageCount, 1)
            } else {
                XCTAssertNotNil(imageType(data), "\(target)")
            }
        }
    }

    func testJPGHasWhiteNotBlackBackground() async throws {
        let output = try await UniversalConverter.convert(try samplePNG(), kind: .image, to: .jpg)[0]
        let image = UIImage(data: output.data)!.cgImage!
        var pixel = [UInt8](repeating: 0, count: 4)
        let ctx = CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        // Sample the transparent right half.
        ctx.draw(image, in: CGRect(x: -150, y: -50, width: CGFloat(image.width), height: CGFloat(image.height)))
        XCTAssertGreaterThan(pixel[0], 230)
        XCTAssertGreaterThan(pixel[1], 230)
    }

    func testCombineImages() throws {
        let out = try UniversalConverter.combineImages([try samplePNG("a.png"), try samplePNG("b.png")], name: "x", quality: 0.8)
        XCTAssertEqual(PDFDocument(data: out.data)?.pageCount, 2)
    }

    // MARK: Text / web / office →

    func testTextToEverything() async throws {
        let url = try write(Data("Merhaba dünya — çğış\nSecond line".utf8), "note.txt")
        for target in UniversalConverter.targets(for: .text, ext: "txt") {
            let outputs = try await UniversalConverter.convert(url, kind: .text, to: target)
            let data = try contents(outputs[0])
            XCTAssertGreaterThan(data.count, 10, "\(target)")
            switch target {
            case .pdf:
                XCTAssertTrue((PDFDocument(data: data)?.string ?? "").contains("Merhaba"))
            case .html:
                XCTAssertTrue(String(decoding: data, as: UTF8.self).contains("<p>Merhaba dünya — çğış</p>"))
            case .rtf:
                let rtf = try NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.rtf],
                                                 documentAttributes: nil)
                XCTAssertTrue(rtf.string.contains("çğış"))
            default:
                break
            }
        }
    }

    func testWebPageToWord() async throws {
        let url = try write(Data("<html><body><h1>Menu</h1><p>Soup of the day</p></body></html>".utf8), "page.html")
        let out = try await UniversalConverter.convert(url, kind: .web, to: .docx)[0]
        XCTAssertEqual(out.data.prefix(2), Data("PK".utf8))
        let txt = try await UniversalConverter.convert(url, kind: .web, to: .txt)[0]
        XCTAssertTrue(String(decoding: txt.data, as: UTF8.self).contains("Soup of the day"))
    }

    // MARK: Audio / video →

    func testAudioConversions() async throws {
        let url = try sampleWAV()
        for target in UniversalConverter.targets(for: .audio, ext: "wav") {
            let output = try await UniversalConverter.convert(url, kind: .audio, to: target)[0]
            let file = try AVAudioFile(forReading: try XCTUnwrap(output.fileURL))
            XCTAssertEqual(Double(file.length) / file.fileFormat.sampleRate, 1.0, accuracy: 0.1, "\(target)")
        }
    }

    func testVideoConversions() async throws {
        let url = try await sampleMovie()
        let mp4 = try await UniversalConverter.convert(url, kind: .video, to: .mp4)[0]
        let duration = try await AVURLAsset(url: try XCTUnwrap(mp4.fileURL)).load(.duration).seconds
        XCTAssertEqual(duration, 1.0, accuracy: 0.2)

        let gif = try await UniversalConverter.convert(url, kind: .video, to: .gif)[0]
        let source = try XCTUnwrap(CGImageSourceCreateWithData(gif.data as CFData, nil))
        XCTAssertGreaterThan(CGImageSourceGetCount(source), 5, "animated GIF")

        do {
            _ = try await UniversalConverter.convert(url, kind: .video, to: .m4a)
            XCTFail("a silent video has no audio to extract")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("no sound"))
        }
    }
}

// MARK: - Document engine (Markdown, CSV, JSON, Word, Excel, PowerPoint)

final class DocumentEngineTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("docs-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func write(_ text: String, _ name: String) throws -> URL {
        let url = dir.appendingPathComponent(name)
        try Data(text.utf8).write(to: url)
        return url
    }

    private func convert(_ url: URL, to target: TargetFormat) async throws -> OutputFile {
        try await UniversalConverter.convert(url, kind: UniversalConverter.detect(url), to: target)[0]
    }

    private let markdown = """
    # Project Plan

    Some **bold** and *italic* text with `code` and a [link](https://example.com). snake_case stays.

    ## Tasks
    - First item
    - Second item
      - Nested item
    1. One
    2. Two

    > A wise quote

    | Name | Qty |
    | --- | ---: |
    | Apple | 3 |
    | Pear | 12 |

    ```
    let x = 1
    ```

    ---
    Çalışma ğüşiöç
    """

    func testMarkdownParsing() {
        let doc = Markdown.parse(markdown, title: "Plan")
        XCTAssertEqual(doc.blocks.first, .heading(level: 1, runs: [TextRun(text: "Project Plan")]))
        guard case .paragraph(let runs) = doc.blocks[1] else { return XCTFail("paragraph expected") }
        XCTAssertTrue(runs.contains(TextRun(text: "bold", bold: true)))
        XCTAssertTrue(runs.contains(TextRun(text: "italic", italic: true)))
        XCTAssertTrue(runs.contains(TextRun(text: "code", code: true)))
        XCTAssertTrue(runs.contains(TextRun(text: "link", link: "https://example.com")))
        XCTAssertTrue(runs.plain.contains("snake_case stays"))
        XCTAssertTrue(doc.blocks.contains(.listItem(ordered: false, number: 0, level: 1, runs: [TextRun(text: "Nested item")])))
        XCTAssertTrue(doc.blocks.contains(.listItem(ordered: true, number: 2, level: 0, runs: [TextRun(text: "Two")])))
        XCTAssertTrue(doc.blocks.contains(.quote([TextRun(text: "A wise quote")])))
        XCTAssertTrue(doc.blocks.contains(.table([["Name", "Qty"], ["Apple", "3"], ["Pear", "12"]])))
        XCTAssertTrue(doc.blocks.contains(.code("let x = 1")))
        XCTAssertTrue(doc.blocks.contains(.rule))
    }

    func testMarkdownToEverything() async throws {
        let url = try write(markdown, "plan.md")
        for target in UniversalConverter.targets(for: .markdown, ext: "md") {
            let output = try await convert(url, to: target)
            XCTAssertEqual(output.ext, target.ext)
            XCTAssertGreaterThan(output.data.count, 50, "\(target)")
        }
        let html = String(decoding: try await convert(url, to: .html).data, as: UTF8.self)
        for piece in ["<h1>Project Plan</h1>", "<strong>bold</strong>", "<em>italic</em>", "<code>code</code>",
                      "<a href=\"https://example.com\">link</a>", "<li>First item</li>", "<ol start=\"1\">",
                      "<blockquote>", "<th>Name</th>", "<td>Pear</td>", "<pre><code>let x = 1</code></pre>", "Çalışma ğüşiöç"] {
            XCTAssertTrue(html.contains(piece), "HTML is missing \(piece)")
        }
        let text = String(decoding: try await convert(url, to: .txt).data, as: UTF8.self)
        XCTAssertFalse(text.contains("**"), "plain text must not contain Markdown syntax")
        XCTAssertTrue(text.contains("• First item"))

        let pdf = PDFDocument(data: try await convert(url, to: .pdf).data)
        XCTAssertTrue((pdf?.string ?? "").contains("Project Plan"))
        XCTAssertTrue((pdf?.string ?? "").contains("Pear"))
    }

    func testMarkdownWordRoundTrip() async throws {
        let docx = try await convert(try write(markdown, "plan.md"), to: .docx)
        let parsed = try DocxReader.read(docx.data, title: "x")
        XCTAssertEqual(parsed.blocks.first, .heading(level: 1, runs: [TextRun(text: "Project Plan")]))
        XCTAssertTrue(parsed.blocks.contains(.heading(level: 2, runs: [TextRun(text: "Tasks")])))
        XCTAssertTrue(parsed.tables.contains([["Name", "Qty"], ["Apple", "3"], ["Pear", "12"]]))
        guard case .paragraph(let runs) = parsed.blocks[1] else { return XCTFail("paragraph expected") }
        XCTAssertTrue(runs.contains { $0.bold && $0.text == "bold" })
        XCTAssertTrue(runs.contains { $0.italic && $0.text == "italic" })
        XCTAssertTrue(parsed.blocks.contains { if case .listItem(_, _, _, let r) = $0 { return r.plain == "First item" }; return false })

        // And Word → Markdown keeps the structure.
        let wordURL = dir.appendingPathComponent("plan.docx")
        try docx.data.write(to: wordURL)
        let md = String(decoding: try await convert(wordURL, to: .md).data, as: UTF8.self)
        XCTAssertTrue(md.contains("# Project Plan"))
        XCTAssertTrue(md.contains("**bold**"))
        XCTAssertTrue(md.contains("| Apple | 3 |"))
    }

    func testCSVParsing() {
        XCTAssertEqual(CSV.parse("a,b\n1,\"x, y\"\n2,\"say \"\"hi\"\"\"\n"), [["a", "b"], ["1", "x, y"], ["2", "say \"hi\""]])
        XCTAssertEqual(CSV.parse("ad;soyad\r\nAli;Yılmaz\r\n"), [["ad", "soyad"], ["Ali", "Yılmaz"]], "semicolon CSV from Turkish Excel")
        XCTAssertEqual(CSV.parse("\u{FEFF}a\tb\n1\t2", delimiter: "\t"), [["a", "b"], ["1", "2"]])
        XCTAssertEqual(CSV.parse("a,b\n\"multi\nline\",2\n"), [["a", "b"], ["multi\nline", "2"]])
        XCTAssertEqual(CSV.number("12"), 12)
        XCTAssertEqual(CSV.number("-3.5"), -3.5)
        XCTAssertNil(CSV.number("007"))
        XCTAssertNil(CSV.number("nan"))
        XCTAssertNil(CSV.number("+905551234567"))
    }

    func testCSVToExcelJSONAndBack() async throws {
        let csv = try write("Ürün,Adet,Fiyat\nElma,3,4.5\n\"Armut, sarı\",12,1\n", "stok.csv")

        let xlsx = try await convert(csv, to: .xlsx)
        XCTAssertEqual(xlsx.data.prefix(2), Data("PK".utf8))
        let sheets = try XlsxReader.read(xlsx.data)
        XCTAssertEqual(sheets.count, 1)
        XCTAssertEqual(sheets[0].rows, [["Ürün", "Adet", "Fiyat"], ["Elma", "3", "4.5"], ["Armut, sarı", "12", "1"]])
        let entries = try ZipReader(data: xlsx.data).entries
        XCTAssertTrue(String(decoding: entries["xl/worksheets/sheet1.xml"]!, as: UTF8.self).contains("<v>4.5</v>"), "numbers stay numbers")
        for (name, data) in entries { XCTAssertTrue(XMLParser(data: data).parse(), "\(name) must be well-formed") }

        let json = try await convert(csv, to: .json)
        let objects = try JSONSerialization.jsonObject(with: json.data) as! [[String: Any]]
        XCTAssertEqual(objects.count, 2)
        XCTAssertEqual(objects[1]["Ürün"] as? String, "Armut, sarı")
        XCTAssertEqual(objects[1]["Adet"] as? Int, 12)
        XCTAssertEqual(objects[0]["Fiyat"] as? Double, 4.5)
        XCTAssertTrue(String(decoding: json.data, as: UTF8.self).range(of: "Ürün")!.lowerBound
                      < String(decoding: json.data, as: UTF8.self).range(of: "Fiyat")!.lowerBound, "column order kept")

        // Excel → CSV, and JSON → CSV.
        let xlsxURL = dir.appendingPathComponent("stok.xlsx")
        try xlsx.data.write(to: xlsxURL)
        let backToCSV = String(decoding: try await convert(xlsxURL, to: .csv).data, as: UTF8.self)
        XCTAssertTrue(backToCSV.hasPrefix("\u{FEFF}Ürün,Adet,Fiyat"))
        XCTAssertTrue(backToCSV.contains("\"Armut, sarı\",12,1"))

        let jsonURL = dir.appendingPathComponent("stok.json")
        try json.data.write(to: jsonURL)
        let fromJSON = CSV.parse(String(decoding: try await convert(jsonURL, to: .csv).data, as: UTF8.self))
        XCTAssertEqual(fromJSON.first, ["Ürün", "Adet", "Fiyat"])
        XCTAssertEqual(fromJSON.count, 3)

        let markdownTable = String(decoding: try await convert(csv, to: .md).data, as: UTF8.self)
        XCTAssertTrue(markdownTable.contains("| Ürün | Adet | Fiyat |"))
        let pdf = PDFDocument(data: try await convert(csv, to: .pdf).data)
        XCTAssertTrue((pdf?.string ?? "").contains("Elma"))
    }

    func testTableFormatsNeedATable() async throws {
        let text = try write("Just a sentence.", "note.md")
        do {
            _ = try UniversalConverter.write(try await UniversalConverter.document(text, kind: .markdown, name: "n"), as: .csv, name: "n")
            XCTFail("CSV from a document without a table should fail")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("table"))
        }
    }

    func testJSONNestedObjectBecomesPrettyText() async throws {
        let url = try write(#"{"name":"PDF Studio","version":1,"tags":{"a":true}}"#, "config.json")
        let text = String(decoding: try await convert(url, to: .txt).data, as: UTF8.self)
        XCTAssertTrue(text.contains("\"name\" : \"PDF Studio\""))
    }

    func testPowerPointReading() async throws {
        func slide(_ texts: [String]) -> Data {
            let paragraphs = texts.map { "<a:p><a:r><a:t>\($0)</a:t></a:r></a:p>" }.joined()
            return Data("""
            <?xml version="1.0" encoding="UTF-8"?><p:sld xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main"><p:cSld><p:spTree><p:sp><p:txBody>\(paragraphs)</p:txBody></p:sp></p:spTree></p:cSld></p:sld>
            """.utf8)
        }
        var zip = ZipWriter()
        zip.add(path: "ppt/slides/slide2.xml", data: slide(["Results", "Revenue grew 20%"]))
        zip.add(path: "ppt/slides/slide1.xml", data: slide(["Welcome", "Agenda for today"]))
        zip.add(path: "ppt/slides/slide10.xml", data: slide(["Thanks"]))
        let url = dir.appendingPathComponent("deck.pptx")
        try zip.finish().write(to: url)

        let md = String(decoding: try await convert(url, to: .md).data, as: UTF8.self)
        let first = md.range(of: "Slide 1: Welcome")!, second = md.range(of: "Slide 2: Results")!, tenth = md.range(of: "Slide 3: Thanks")!
        XCTAssertTrue(first.lowerBound < second.lowerBound && second.lowerBound < tenth.lowerBound, "slides in numeric order")
        XCTAssertTrue(md.contains("Revenue grew 20%"))
        let docx = try await convert(url, to: .docx)
        XCTAssertTrue(try DocxReader.read(docx.data, title: "").blocks.contains(.paragraph([TextRun(text: "Agenda for today")])))
    }

    func testZipDeflateRoundTrip() throws {
        var zip = ZipWriter()
        let big = Data(String(repeating: "PDF Studio compresses well. ", count: 500).utf8)
        zip.add(path: "a.txt", data: big)
        zip.add(path: "empty.txt", data: Data())
        let archive = zip.finish()
        XCTAssertLessThan(archive.count, big.count / 5, "DEFLATE is used")
        let entries = try ZipReader(data: archive).entries
        XCTAssertEqual(entries["a.txt"], big)
        XCTAssertEqual(entries["empty.txt"], Data())
        XCTAssertThrowsError(try ZipReader(data: Data("not a zip".utf8)))
    }
}

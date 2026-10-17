import AVFoundation
import ImageIO
import PDFKit
import UIKit
import UniformTypeIdentifiers

/// What a picked file is, detected from its extension and, failing that, its contents.
enum FileKind: Equatable {
    case pdf, image, word, spreadsheet, presentation, office, markdown, text, table, json, web, video, audio, unsupported

    var title: String {
        switch self {
        case .pdf: "PDF document"
        case .image: "Image"
        case .word: "Word document"
        case .spreadsheet: "Excel spreadsheet"
        case .presentation: "PowerPoint presentation"
        case .office: "Office document"
        case .markdown: "Markdown"
        case .text: "Text document"
        case .table: "CSV table"
        case .json: "JSON data"
        case .web: "Web page"
        case .video: "Video"
        case .audio: "Audio"
        case .unsupported: "Unsupported file"
        }
    }

    var icon: String {
        switch self {
        case .pdf: "doc.fill"
        case .image: "photo.fill"
        case .word: "doc.text.fill"
        case .spreadsheet, .table: "tablecells.fill"
        case .presentation: "rectangle.on.rectangle.angled.fill"
        case .office: "doc.richtext.fill"
        case .markdown: "number"
        case .text: "doc.plaintext.fill"
        case .json: "curlybraces"
        case .web: "globe"
        case .video: "film.fill"
        case .audio: "waveform"
        case .unsupported: "questionmark.square.dashed"
        }
    }
}

enum TargetFormat: String, CaseIterable, Identifiable {
    case pdf, docx, xlsx, csv, json, txt, md, rtf, html, jpg, png, heic, tiff, bmp, gif, mp4, mov, m4a, wav, aiff, caf

    var id: String { rawValue }
    var ext: String { rawValue }

    var title: String {
        switch self {
        case .pdf: "PDF"
        case .docx: "Word"
        case .xlsx: "Excel"
        case .txt: "Text"
        case .md: "Markdown"
        default: rawValue.uppercased()
        }
    }

    var icon: String {
        switch self {
        case .pdf: "doc.fill"
        case .docx: "doc.text.fill"
        case .xlsx, .csv: "tablecells"
        case .json: "curlybraces"
        case .txt: "text.alignleft"
        case .md: "number"
        case .rtf: "doc.richtext"
        case .html: "chevron.left.forwardslash.chevron.right"
        case .jpg, .png, .heic, .tiff, .bmp: "photo"
        case .gif: "photo.stack"
        case .mp4, .mov: "film"
        case .m4a, .wav, .aiff, .caf: "waveform"
        }
    }

    var usesQuality: Bool { self == .jpg || self == .heic }
    var needsTable: Bool { self == .csv || self == .xlsx || self == .json }

    var imageType: UTType? {
        switch self {
        case .jpg: .jpeg
        case .png: .png
        case .heic: .heic
        case .tiff: .tiff
        case .bmp: .bmp
        case .gif: .gif
        default: nil
        }
    }
}

enum UniversalConverter {
    static let extensions: [FileKind: Set<String>] = [
        .word: ["docx", "docm", "dotx"],
        .spreadsheet: ["xlsx", "xlsm"],
        .presentation: ["pptx", "ppsx"],
        .office: ["doc", "xls", "ppt", "pages", "numbers", "key"],
        .markdown: ["md", "markdown", "mdown", "mkd"],
        .table: ["csv", "tsv"],
        .json: ["json", "geojson"],
        .text: ["txt", "text", "log", "rtf", "xml", "yaml", "yml", "ini", "conf", "srt", "vtt"],
        .web: ["html", "htm", "xhtml", "webarchive", "svg"],
    ]

    // MARK: Detection

    static func detect(_ url: URL) -> FileKind {
        let ext = url.pathExtension.lowercased()
        if let kind = extensions.first(where: { $0.value.contains(ext) })?.key { return kind }
        if let type = UTType(filenameExtension: ext) {
            if type.conforms(to: .pdf) { return .pdf }
            if type.conforms(to: .image) { return .image }
            if type.conforms(to: .movie) || type.conforms(to: .video) { return .video }
            if type.conforms(to: .audio) { return .audio }
            if type.conforms(to: .html) { return .web }
            if type.conforms(to: .commaSeparatedText) { return .table }
            if type.conforms(to: .json) { return .json }
            if type.conforms(to: .text) { return .text }
        }
        // Missing or wrong extension: look at the bytes.
        if let handle = try? FileHandle(forReadingFrom: url) {
            defer { try? handle.close() }
            if let head = try? handle.read(upToCount: 5), head.starts(with: Array("%PDF-".utf8)) { return .pdf }
        }
        if let source = CGImageSourceCreateWithURL(url as CFURL, nil), CGImageSourceGetCount(source) > 0,
           CGImageSourceGetStatus(source) == .statusComplete {
            return .image
        }
        return .unsupported
    }

    /// Formats a kind of file can become, best first. The file's own format is left out.
    static func targets(for kind: FileKind, ext: String = "") -> [TargetFormat] {
        let all: [TargetFormat]
        switch kind {
        case .pdf: all = [.docx, .jpg, .png, .txt, .md, .html, .rtf, .heic, .tiff, .bmp]
        case .image: all = [.pdf, .jpg, .png, .heic, .tiff, .bmp, .gif, .txt, .docx, .md]
        case .word: all = [.pdf, .md, .txt, .html, .rtf, .jpg, .png]
        case .spreadsheet: all = [.pdf, .csv, .json, .html, .md, .docx, .txt]
        case .presentation: all = [.pdf, .docx, .md, .txt, .html, .jpg, .png]
        case .office: all = [.pdf, .docx, .txt, .md, .jpg, .png]
        case .markdown: all = [.pdf, .docx, .html, .rtf, .txt, .jpg, .png]
        case .text: all = [.pdf, .docx, .md, .rtf, .html, .jpg]
        case .table: all = [.xlsx, .json, .csv, .pdf, .docx, .html, .md, .txt]
        case .json: all = [.csv, .xlsx, .pdf, .html, .md, .txt]
        case .web: all = [.pdf, .docx, .md, .txt, .jpg, .png]
        case .video: all = [.mp4, .mov, .m4a, .wav, .gif, .jpg]
        case .audio: all = [.m4a, .wav, .aiff, .caf]
        case .unsupported: all = []
        }
        let own = ext.lowercased() == "jpeg" ? "jpg" : ext.lowercased()
        return all.filter { $0.ext != own }
    }

    /// A short line such as "3 pages", "4032 × 3024", "1:24", "12 rows".
    static func describe(_ url: URL, kind: FileKind) async -> String {
        let size = url.fileSize.formattedFileSize
        switch kind {
        case .pdf:
            guard let doc = PDFDocument(url: url) else { return size }
            if doc.isLocked { return "Password protected · \(size)" }
            return "\(doc.pageCount) page\(doc.pageCount == 1 ? "" : "s") · \(size)"
        case .image:
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                  let w = props[kCGImagePropertyPixelWidth] as? Int, let h = props[kCGImagePropertyPixelHeight] as? Int
            else { return size }
            return "\(w) × \(h) · \(size)"
        case .video, .audio:
            guard let seconds = try? await AVURLAsset(url: url).load(.duration).seconds, seconds.isFinite else { return size }
            return "\(Int(seconds) / 60):\(String(format: "%02d", Int(seconds) % 60)) · \(size)"
        case .table:
            let rows = (try? readTextFile(url)).map { CSV.parse($0, delimiter: url.pathExtension.lowercased() == "tsv" ? "\t" : nil) } ?? []
            return "\(max(rows.count - 1, 0)) rows · \(rows.first?.count ?? 0) columns · \(size)"
        default:
            let type = UTType(filenameExtension: url.pathExtension)?.localizedDescription ?? url.pathExtension.uppercased()
            return "\(type) · \(size)"
        }
    }

    // MARK: Conversion

    static func convert(_ url: URL, kind: FileKind, to target: TargetFormat, quality: CGFloat = 0.85,
                        progress: @escaping (Int, Int) -> Void = { _, _ in }) async throws -> [OutputFile] {
        let name = url.deletingPathExtension().lastPathComponent
        switch kind {
        case .video: return [try await convertVideo(url, name: name, to: target, quality: quality)]
        case .audio: return [try convertAudio(url, name: name, to: target)]
        case .unsupported: throw PDFToolError.message("This type of file can't be converted.")
        default: break
        }

        if target == .pdf {
            return [OutputFile(data: try await pdfData(url, kind: kind, name: name, progress: progress), name: name, ext: "pdf")]
        }
        if target.imageType != nil {
            if kind == .image {
                return [OutputFile(data: try encode(try loadImage(url), as: target, quality: quality), name: name, ext: target.ext)]
            }
            let pdf = try await pdfData(url, kind: kind, name: name, progress: progress)
            guard let doc = PDFDocument(data: pdf) else { throw PDFToolError.unreadable(url.lastPathComponent) }
            return try pages(of: doc, name: name, as: target, quality: quality, progress: progress)
        }

        let document = try await self.document(url, kind: kind, name: name, progress: progress)
        return [try write(document, as: target, name: name)]
    }

    /// Reads any text-bearing file into the common document structure.
    static func document(_ url: URL, kind: FileKind, name: String,
                         progress: @escaping (Int, Int) -> Void = { _, _ in }) async throws -> RichDocument {
        let document: RichDocument
        let ext = url.pathExtension.lowercased()
        switch kind {
        case .markdown:
            document = Markdown.parse(try readTextFile(url), title: name)
        case .text:
            if ext == "rtf" {
                let attributed = try NSAttributedString(url: url, options: [.documentType: NSAttributedString.DocumentType.rtf],
                                                        documentAttributes: nil)
                document = RichDocument.plain(attributed.string, title: name)
            } else if ["xml", "yaml", "yml", "ini", "conf", "log"].contains(ext) {
                document = RichDocument(title: name, blocks: [.code(try readTextFile(url))])
            } else {
                document = RichDocument.plain(try readTextFile(url), title: name)
            }
        case .table:
            let rows = CSV.parse(try readTextFile(url), delimiter: ext == "tsv" ? "\t" : nil)
            document = RichDocument(title: name, blocks: rows.isEmpty ? [] : [.table(rows)])
        case .json:
            let data = try Data(contentsOf: url)
            if let rows = JSONTable.table(from: data) {
                document = RichDocument(title: name, blocks: [.table(rows)])
            } else if let pretty = JSONTable.prettyPrinted(data) {
                document = RichDocument(title: name, blocks: [.code(pretty)])
            } else {
                throw PDFToolError.message("\"\(url.lastPathComponent)\" is not valid JSON.")
            }
        case .word:
            document = try DocxReader.read(try Data(contentsOf: url), title: name)
        case .spreadsheet:
            let sheets = try XlsxReader.read(try Data(contentsOf: url))
            var blocks: [DocBlock] = []
            for sheet in sheets {
                if sheets.count > 1 { blocks.append(.heading(level: 2, runs: [TextRun(text: sheet.name)])) }
                blocks.append(.table(sheet.rows))
            }
            document = RichDocument(title: name, blocks: blocks)
        case .presentation:
            document = try PptxReader.read(try Data(contentsOf: url), title: name)
        case .pdf:
            guard let pdf = PDFDocument(url: url) else { throw PDFToolError.unreadable(url.lastPathComponent) }
            if pdf.isLocked { throw locked(url) }
            document = RichDocument.pages(try TextExtractor.pages(of: pdf, useOCR: true, progress: progress), title: name)
        case .image:
            let text = OCRService.text(of: try OCRService.recognize(UIImage(cgImage: try loadImage(url))))
            document = RichDocument.plain(text, title: name)
        case .office, .web:
            let pdf = try await WebPDFRenderer.pdf(fromFile: url, paper: .a4)
            guard let doc = PDFDocument(data: pdf) else { throw PDFToolError.unreadable(url.lastPathComponent) }
            document = RichDocument.pages(try TextExtractor.pages(of: doc, useOCR: true, progress: progress), title: name)
        case .video, .audio, .unsupported:
            throw PDFToolError.message("This file has no text to convert.")
        }
        guard document.hasText else { throw PDFToolError.message("No text was found in \"\(url.lastPathComponent)\".") }
        return document
    }

    static func write(_ document: RichDocument, as target: TargetFormat, name: String) throws -> OutputFile {
        if target.needsTable, document.tables.isEmpty {
            throw PDFToolError.message("\(target.title) needs a table, and none was found in this file.")
        }
        let data: Data
        switch target {
        case .docx: data = DocxWriter.document(document)
        case .md: data = Data(Markdown.write(document).utf8)
        case .html: data = Data(HTMLWriter.write(document).utf8)
        case .rtf: data = try RTFWriter.write(document)
        case .txt: data = Data(PlainTextWriter.write(document).utf8)
        case .csv: data = CSV.write(document.tables[0])
        case .json: data = JSONTable.json(from: document.tables[0])
        case .xlsx:
            let tables = document.tables
            data = XlsxWriter.workbook(tables.enumerated().map { (tables.count == 1 ? name : "Sheet\($0 + 1)", $1) })
        default: throw PDFToolError.message("\(target.title) is not a document format.")
        }
        return OutputFile(data: data, name: name, ext: target.ext)
    }

    /// A PDF that looks as close to the original as possible.
    static func pdfData(_ url: URL, kind: FileKind, name: String,
                        progress: @escaping (Int, Int) -> Void = { _, _ in }) async throws -> Data {
        switch kind {
        case .pdf:
            guard let doc = PDFDocument(url: url) else { throw PDFToolError.unreadable(url.lastPathComponent) }
            if doc.isLocked { throw locked(url) }
            return try Data(contentsOf: url)
        case .image:
            return PDFService.imagesToPDF([UIImage(cgImage: try loadImage(url))], pageSize: .fit, margin: .none)
        case .office, .web:
            return try await WebPDFRenderer.pdf(fromFile: url, paper: .a4)
        case .word, .spreadsheet, .presentation:
            // WebKit renders Office files with their original layout; fall back to the parsed content.
            if let pdf = try? await WebPDFRenderer.pdf(fromFile: url, paper: .a4),
               let doc = PDFDocument(data: pdf), doc.pageCount > 0, (doc.string ?? "").count > 3 {
                return pdf
            }
            return try await renderHTML(HTMLWriter.write(try await document(url, kind: kind, name: name)), name: name)
        case .text where url.pathExtension.lowercased() == "rtf":
            return try await WebPDFRenderer.pdf(fromFile: url, paper: .a4)
        default:
            return try await renderHTML(HTMLWriter.write(try await document(url, kind: kind, name: name, progress: progress)), name: name)
        }
    }

    private static func renderHTML(_ html: String, name: String) async throws -> Data {
        let url = TempFiles.newURL(ext: "html")
        try html.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }
        return try await WebPDFRenderer.pdf(fromFile: url, paper: .a4)
    }

    private static func locked(_ url: URL) -> Error {
        PDFToolError.message("\"\(url.lastPathComponent)\" is password protected. Unlock it first with Unlock PDF.")
    }

    private static func pages(of doc: PDFDocument, name: String, as target: TargetFormat, quality: CGFloat,
                              progress: @escaping (Int, Int) -> Void) throws -> [OutputFile] {
        var outputs: [OutputFile] = []
        for index in 0..<doc.pageCount {
            progress(index + 1, doc.pageCount)
            guard let page = doc.page(at: index) else { continue }
            let data = try autoreleasepool {
                try encode(PDFService.renderImage(page, scale: 2).cgImage!, as: target, quality: quality)
            }
            outputs.append(OutputFile(data: data, name: doc.pageCount == 1 ? name : "\(name)_page_\(index + 1)", ext: target.ext))
        }
        return outputs
    }

    /// Several images into one multi-page PDF.
    static func combineImages(_ urls: [URL], name: String, quality: CGFloat) throws -> OutputFile {
        let images = try urls.map { UIImage(cgImage: try loadImage($0)) }
        return OutputFile(data: PDFService.imagesToPDF(images, pageSize: .fit, margin: .none, quality: quality),
                          name: name, ext: "pdf")
    }

    // MARK: Images

    /// Decodes any image ImageIO understands (HEIC, PNG, WebP, TIFF, RAW…) with its orientation applied.
    static func loadImage(_ url: URL) throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceCreateThumbnailWithTransform: true,
                  kCGImageSourceThumbnailMaxPixelSize: 6000,
              ] as CFDictionary)
        else { throw PDFToolError.unreadable(url.lastPathComponent) }
        return image
    }

    static func encode(_ image: CGImage, as target: TargetFormat, quality: CGFloat) throws -> Data {
        guard let type = target.imageType else { throw PDFToolError.message("\(target.title) is not an image format.") }
        // Formats without transparency get a white background instead of black.
        let source = (target == .jpg || target == .heic) ? flattened(image) : image
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil) else {
            throw PDFToolError.message("\(target.title) isn't supported on this device.")
        }
        CGImageDestinationAddImage(destination, source, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw PDFToolError.message("\(target.title) conversion failed.") }
        return data as Data
    }

    private static func flattened(_ image: CGImage) -> CGImage {
        let size = CGSize(width: image.width, height: image.height)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            UIImage(cgImage: image).draw(in: CGRect(origin: .zero, size: size))
        }.cgImage ?? image
    }

    // MARK: Video & audio

    private static func convertVideo(_ url: URL, name: String, to target: TargetFormat, quality: CGFloat) async throws -> OutputFile {
        let asset = AVURLAsset(url: url)
        switch target {
        case .gif:
            return OutputFile(data: try await gif(from: asset), name: name, ext: "gif")
        case .jpg:
            // A still from the middle of the first two seconds.
            let duration = try await asset.load(.duration).seconds
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            let frame = try await generator.image(at: CMTime(seconds: min(1, duration / 2), preferredTimescale: 600)).image
            return OutputFile(data: try encode(frame, as: .jpg, quality: quality), name: "\(name)_frame", ext: "jpg")
        case .wav:
            let m4a = try await convertVideo(url, name: name, to: .m4a, quality: quality)
            guard let source = m4a.fileURL else { throw PDFToolError.message("The conversion failed.") }
            defer { try? FileManager.default.removeItem(at: source) }
            return try convertAudio(source, name: name, to: .wav)
        default:
            break
        }
        if target == .m4a, try await asset.loadTracks(withMediaType: .audio).isEmpty {
            throw PDFToolError.message("This video has no sound to extract.")
        }
        let preset = target == .m4a ? AVAssetExportPresetAppleM4A : AVAssetExportPresetHighestQuality
        guard let session = AVAssetExportSession(asset: asset, presetName: preset) else {
            throw PDFToolError.message("This video can't be converted.")
        }
        let output = TempFiles.newURL(ext: target.ext)
        session.outputURL = output
        session.outputFileType = target == .mp4 ? .mp4 : target == .mov ? .mov : .m4a
        session.shouldOptimizeForNetworkUse = true
        await session.export()
        guard session.status == .completed else {
            throw PDFToolError.message(session.error?.localizedDescription ?? "The conversion failed.")
        }
        return OutputFile(data: Data(), name: name, ext: target.ext, fileURL: output)
    }

    /// Up to 15 seconds at 10 fps, 480 px wide, looping forever.
    static func gif(from asset: AVURLAsset) async throws -> Data {
        let duration = try await asset.load(.duration).seconds
        let fps = 10.0
        let count = max(1, Int(min(duration, 15) * fps))
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 480, height: 480)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = CMTime(value: 1, timescale: 20)

        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.gif.identifier as CFString, count, nil) else {
            throw PDFToolError.message("GIF isn't supported on this device.")
        }
        CGImageDestinationSetProperties(destination, [
            kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0],
        ] as CFDictionary)
        let frameProperties = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 1 / fps]] as CFDictionary
        for index in 0..<count {
            let time = CMTime(seconds: Double(index) / fps, preferredTimescale: 600)
            let frame = try await generator.image(at: time).image
            CGImageDestinationAddImage(destination, frame, frameProperties)
        }
        guard CGImageDestinationFinalize(destination) else { throw PDFToolError.message("GIF conversion failed.") }
        return data as Data
    }

    private static func convertAudio(_ url: URL, name: String, to target: TargetFormat) throws -> OutputFile {
        let output = TempFiles.newURL(ext: target.ext)
        try transcodeAudio(from: url, to: output, format: target)
        return OutputFile(data: Data(), name: name, ext: target.ext, fileURL: output)
    }

    private static func transcodeAudio(from source: URL, to destination: URL, format target: TargetFormat) throws {
        let input = try AVAudioFile(forReading: source)
        let format = input.processingFormat
        var settings: [String: Any] = [
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: format.channelCount,
        ]
        switch target {
        case .m4a:
            settings[AVFormatIDKey] = kAudioFormatMPEG4AAC
            settings[AVEncoderBitRateKey] = 192_000
        case .wav, .aiff, .caf:
            settings[AVFormatIDKey] = kAudioFormatLinearPCM
            settings[AVLinearPCMBitDepthKey] = 16
            settings[AVLinearPCMIsFloatKey] = false
            settings[AVLinearPCMIsBigEndianKey] = target == .aiff
        default:
            throw PDFToolError.message("\(target.title) is not an audio format.")
        }
        // The output file is closed when it goes out of scope at the end of this function.
        let output = try AVAudioFile(forWriting: destination, settings: settings,
                                     commonFormat: format.commonFormat, interleaved: format.isInterleaved)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 32_768) else {
            throw PDFToolError.message("Audio conversion failed.")
        }
        while input.framePosition < input.length {
            try input.read(into: buffer)
            if buffer.frameLength == 0 { break }
            try output.write(from: buffer)
        }
    }
}

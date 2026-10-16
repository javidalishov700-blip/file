import AVFoundation
import ImageIO
import PDFKit
import UIKit
import UniformTypeIdentifiers

/// What a picked file is, detected from its extension and, failing that, its contents.
enum FileKind: Equatable {
    case pdf, image, office, text, web, video, audio, unsupported

    var title: String {
        switch self {
        case .pdf: "PDF document"
        case .image: "Image"
        case .office: "Office document"
        case .text: "Text document"
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
        case .office: "doc.richtext.fill"
        case .text: "doc.plaintext.fill"
        case .web: "globe"
        case .video: "film.fill"
        case .audio: "waveform"
        case .unsupported: "questionmark.square.dashed"
        }
    }
}

enum TargetFormat: String, CaseIterable, Identifiable {
    case pdf, docx, txt, md, rtf, html, jpg, png, heic, tiff, gif, mp4, mov, m4a, wav, aiff

    var id: String { rawValue }
    var ext: String { rawValue }

    var title: String {
        switch self {
        case .pdf: "PDF"
        case .docx: "Word"
        case .txt: "Text"
        case .md: "Markdown"
        case .rtf: "RTF"
        case .html: "HTML"
        default: rawValue.uppercased()
        }
    }

    var icon: String {
        switch self {
        case .pdf: "doc.fill"
        case .docx: "doc.text.fill"
        case .txt, .md: "text.alignleft"
        case .rtf: "doc.richtext"
        case .html: "chevron.left.forwardslash.chevron.right"
        case .jpg, .png, .heic, .tiff: "photo"
        case .gif: "photo.stack"
        case .mp4, .mov: "film"
        case .m4a, .wav, .aiff: "waveform"
        }
    }

    var usesQuality: Bool { self == .jpg || self == .heic }

    var imageType: UTType? {
        switch self {
        case .jpg: .jpeg
        case .png: .png
        case .heic: .heic
        case .tiff: .tiff
        case .gif: .gif
        default: nil
        }
    }
}

enum UniversalConverter {
    static let officeExtensions: Set<String> = ["doc", "docx", "xls", "xlsx", "ppt", "pptx", "pages", "numbers", "key"]
    static let textExtensions: Set<String> = ["txt", "text", "md", "markdown", "csv", "tsv", "json", "xml", "log", "rtf"]
    static let webExtensions: Set<String> = ["html", "htm", "xhtml", "webarchive"]

    // MARK: Detection

    static func detect(_ url: URL) -> FileKind {
        let ext = url.pathExtension.lowercased()
        if officeExtensions.contains(ext) { return .office }
        if webExtensions.contains(ext) { return .web }
        if textExtensions.contains(ext) { return .text }
        if let type = UTType(filenameExtension: ext) {
            if type.conforms(to: .pdf) { return .pdf }
            if type.conforms(to: .image) { return .image }
            if type.conforms(to: .movie) || type.conforms(to: .video) { return .video }
            if type.conforms(to: .audio) { return .audio }
            if type.conforms(to: .html) { return .web }
            if type.conforms(to: .text) { return .text }
        }
        // Missing or wrong extension: look at the bytes.
        if let handle = try? FileHandle(forReadingFrom: url) {
            defer { try? handle.close() }
            if let head = try? handle.read(upToCount: 5), head.starts(with: Array("%PDF-".utf8)) { return .pdf }
        }
        if let source = CGImageSourceCreateWithURL(url as CFURL, nil), CGImageSourceGetCount(source) > 0 {
            return .image
        }
        return .unsupported
    }

    /// Formats a kind of file can become, best first. The file's own format is left out.
    static func targets(for kind: FileKind, ext: String = "") -> [TargetFormat] {
        let all: [TargetFormat]
        switch kind {
        case .pdf: all = [.docx, .jpg, .png, .txt, .md, .rtf, .html, .heic, .tiff]
        case .image: all = [.pdf, .jpg, .png, .heic, .tiff, .gif, .txt, .docx]
        case .office: all = [.pdf, .docx, .txt, .jpg, .png]
        case .text: all = [.pdf, .docx, .txt, .rtf, .html, .jpg]
        case .web: all = [.pdf, .docx, .txt, .jpg, .png]
        case .video: all = [.mp4, .mov, .m4a, .gif]
        case .audio: all = [.m4a, .wav, .aiff]
        case .unsupported: all = []
        }
        let own = ext.lowercased() == "jpeg" ? "jpg" : ext.lowercased()
        return all.filter { $0.ext != own }
    }

    /// A short line such as "3 pages", "4032 × 3024", "1:24".
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
        case .pdf:
            guard let doc = PDFDocument(url: url) else { throw PDFToolError.unreadable(url.lastPathComponent) }
            if doc.isLocked { throw PDFToolError.message("\"\(url.lastPathComponent)\" is password protected. Unlock it first with Unlock PDF.") }
            return try fromPDF(doc, name: name, to: target, quality: quality, progress: progress)

        case .image:
            let image = try loadImage(url)
            switch target {
            case .pdf:
                return [OutputFile(data: PDFService.imagesToPDF([UIImage(cgImage: image)], pageSize: .fit, margin: .none,
                                                                quality: quality), name: name, ext: "pdf")]
            case .txt, .docx:
                let text = OCRService.text(of: try OCRService.recognize(UIImage(cgImage: image)))
                guard !text.isEmpty else { throw PDFToolError.message("No text was found in this image.") }
                return [textOutput(text, name: name, as: target)]
            default:
                return [OutputFile(data: try encode(image, as: target, quality: quality), name: name, ext: target.ext)]
            }

        case .office, .web:
            let pdf = try await WebPDFRenderer.pdf(fromFile: url, paper: .a4)
            if target == .pdf { return [OutputFile(data: pdf, name: name, ext: "pdf")] }
            guard let doc = PDFDocument(data: pdf) else { throw PDFToolError.unreadable(url.lastPathComponent) }
            return try fromPDF(doc, name: name, to: target, quality: quality, progress: progress)

        case .text:
            switch target {
            case .pdf, .jpg, .png:
                let pdf = try await WebPDFRenderer.pdf(fromFile: url, paper: .a4)
                if target == .pdf { return [OutputFile(data: pdf, name: name, ext: "pdf")] }
                guard let doc = PDFDocument(data: pdf) else { throw PDFToolError.unreadable(url.lastPathComponent) }
                return try fromPDF(doc, name: name, to: target, quality: quality, progress: progress)
            case .rtf:
                let attributed = try readAttributed(url)
                let data = try attributed.data(from: NSRange(location: 0, length: attributed.length),
                                               documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
                return [OutputFile(data: data, name: name, ext: "rtf")]
            default:
                return [textOutput(try readAttributed(url).string, name: name, as: target)]
            }

        case .video:
            return [try await convertVideo(url, name: name, to: target)]
        case .audio:
            return [try convertAudio(url, name: name, to: target)]
        case .unsupported:
            throw PDFToolError.message("This type of file can't be converted.")
        }
    }

    /// Several images into one multi-page PDF.
    static func combineImages(_ urls: [URL], name: String, quality: CGFloat) throws -> OutputFile {
        let images = try urls.map { UIImage(cgImage: try loadImage($0)) }
        return OutputFile(data: PDFService.imagesToPDF(images, pageSize: .fit, margin: .none, quality: quality),
                          name: name, ext: "pdf")
    }

    private static func fromPDF(_ doc: PDFDocument, name: String, to target: TargetFormat, quality: CGFloat,
                                progress: @escaping (Int, Int) -> Void) throws -> [OutputFile] {
        if let _ = target.imageType {
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
        let pages = try TextExtractor.pages(of: doc, useOCR: true, progress: progress)
        guard pages.contains(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            throw PDFToolError.message("No text was found in this document.")
        }
        switch target {
        case .docx:
            return [OutputFile(data: DocxWriter.document(pages: pages.map(TextExtractor.paragraphs)), name: name, ext: "docx")]
        case .md:
            return [OutputFile(data: Data(TextExtractor.markdown(title: name, pages: pages).utf8), name: name, ext: "md")]
        case .rtf:
            let text = pages.map { TextExtractor.paragraphs($0).joined(separator: "\n\n") }.joined(separator: "\n\u{0C}\n")
            let attributed = NSAttributedString(string: text, attributes: [.font: UIFont.systemFont(ofSize: 12)])
            let data = try attributed.data(from: NSRange(location: 0, length: attributed.length),
                                           documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
            return [OutputFile(data: data, name: name, ext: "rtf")]
        case .html:
            return [OutputFile(data: Data(html(title: name, pages: pages.map(TextExtractor.paragraphs)).utf8), name: name, ext: "html")]
        default:
            return [OutputFile(data: Data(TextExtractor.plainText(pages: pages).utf8), name: name, ext: "txt")]
        }
    }

    private static func textOutput(_ text: String, name: String, as target: TargetFormat) -> OutputFile {
        let lines = text.components(separatedBy: .newlines)
        switch target {
        case .docx: return OutputFile(data: DocxWriter.document(pages: [lines]), name: name, ext: "docx")
        case .html: return OutputFile(data: Data(html(title: name, pages: [lines]).utf8), name: name, ext: "html")
        default: return OutputFile(data: Data(text.utf8), name: name, ext: "txt")
        }
    }

    static func html(title: String, pages: [[String]]) -> String {
        func esc(_ s: String) -> String {
            s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
        }
        let body = pages.map { paragraphs in
            paragraphs.filter { !$0.isEmpty }.map { "<p>\(esc($0))</p>" }.joined(separator: "\n")
        }.joined(separator: "\n<hr>\n")
        return """
        <!doctype html>
        <html><head><meta charset="utf-8"><title>\(esc(title))</title>
        <style>body{font-family:-apple-system,Helvetica,sans-serif;max-width:46rem;margin:2rem auto;padding:0 1rem;line-height:1.5}</style>
        </head><body>
        \(body)
        </body></html>
        """
    }

    private static func readAttributed(_ url: URL) throws -> NSAttributedString {
        if url.pathExtension.lowercased() == "rtf" {
            return try NSAttributedString(url: url, options: [.documentType: NSAttributedString.DocumentType.rtf],
                                          documentAttributes: nil)
        }
        var encoding = String.Encoding.utf8
        let text = (try? String(contentsOf: url, usedEncoding: &encoding))
            ?? (try? String(contentsOf: url, encoding: .windowsCP1254))
            ?? ""
        return NSAttributedString(string: text, attributes: [.font: UIFont.systemFont(ofSize: 12)])
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

    private static func convertVideo(_ url: URL, name: String, to target: TargetFormat) async throws -> OutputFile {
        let asset = AVURLAsset(url: url)
        if target == .gif {
            return OutputFile(data: try await gif(from: asset), name: name, ext: "gif")
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
        case .wav, .aiff:
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

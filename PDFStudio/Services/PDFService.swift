import AVFoundation
import PDFKit
import UIKit

struct OutputFile {
    var data: Data
    var name: String
    var ext: String
    var note: String? = nil
}

typealias ToolWork = @Sendable () async throws -> [OutputFile]

enum PDFToolError: LocalizedError {
    case unreadable(String)
    case noPages
    case invalidRange(String)
    case writeFailed
    case message(String)

    var errorDescription: String? {
        switch self {
        case .unreadable(let name): "\"\(name)\" could not be opened. It may be damaged or not a PDF."
        case .noPages: "The document has no pages."
        case .invalidRange(let text): "\"\(text)\" is not a valid page range. Use a format like 1-3, 5, 8-10."
        case .writeFailed: "The file could not be written."
        case .message(let text): text
        }
    }
}

enum PDFService {

    // MARK: Basics

    static func data(of document: PDFDocument) throws -> Data {
        guard let data = document.dataRepresentation() else { throw PDFToolError.writeFailed }
        return data
    }

    static func pdf(_ document: PDFDocument, name: String, note: String? = nil) throws -> OutputFile {
        OutputFile(data: try data(of: document), name: name, ext: "pdf", note: note)
    }

    /// New document containing copies of the given pages (0-based) in that order.
    static func copyPages(_ document: PDFDocument, indices: [Int]) -> PDFDocument {
        let output = PDFDocument()
        for index in indices {
            guard let page = document.page(at: index)?.copy() as? PDFPage else { continue }
            output.insert(page, at: output.pageCount)
        }
        return output
    }

    static func merge(_ documents: [PDFDocument]) -> PDFDocument {
        let output = PDFDocument()
        for document in documents {
            for index in 0..<document.pageCount {
                guard let page = document.page(at: index)?.copy() as? PDFPage else { continue }
                output.insert(page, at: output.pageCount)
            }
        }
        return output
    }

    /// Parses "1-3, 5, 8-10" into groups of 0-based page indices.
    static func parseRanges(_ text: String, pageCount: Int) throws -> [[Int]] {
        let parts = text.split(whereSeparator: { $0 == "," || $0 == ";" })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard !parts.isEmpty else { throw PDFToolError.invalidRange(text) }
        return try parts.map { part in
            let bounds = part.split(separator: "-", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }
            guard (1...2).contains(bounds.count),
                  let first = Int(bounds[0]),
                  let last = bounds.count == 2 ? (bounds[1].isEmpty ? pageCount : Int(bounds[1])) : first,
                  first >= 1, last >= first, last <= pageCount
            else { throw PDFToolError.invalidRange(part) }
            return Array((first - 1)...(last - 1))
        }
    }

    static func rotate(_ document: PDFDocument, by degrees: Int, pages: [Int]? = nil) {
        for index in pages ?? Array(0..<document.pageCount) {
            guard let page = document.page(at: index) else { continue }
            page.rotation = ((page.rotation + degrees) % 360 + 360) % 360
        }
    }

    // MARK: Rendering

    /// Size of the page as it appears on screen (crop box, rotation applied).
    static func displaySize(_ page: PDFPage) -> CGSize {
        let box = page.bounds(for: .cropBox).size
        return abs(page.rotation) % 180 == 0 ? box : CGSize(width: box.height, height: box.width)
    }

    /// Draws the page into a UIKit-style (top-left origin) context of the page's display size.
    static func drawPage(_ page: PDFPage, in context: CGContext, size: CGSize) {
        context.saveGState()
        context.translateBy(x: 0, y: size.height)
        context.scaleBy(x: 1, y: -1)
        page.transform(context, for: .cropBox)
        page.draw(with: .cropBox, to: context)
        context.restoreGState()
    }

    static func renderImage(_ page: PDFPage, scale: CGFloat) -> UIImage {
        let size = displaySize(page)
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            drawPage(page, in: ctx.cgContext, size: size)
        }
    }

    static func thumbnail(_ page: PDFPage, maxDimension: CGFloat) -> UIImage {
        let size = displaySize(page)
        let scale = min(maxDimension / max(size.width, size.height, 1), 4)
        return renderImage(page, scale: scale)
    }

    /// Redraws every page (vector content is kept) and lets the caller draw on top of it.
    /// The overlay closure receives a top-left-origin context, the page rect and the page index.
    static func stamp(_ document: PDFDocument, overlay: (CGContext, CGRect, Int) -> Void) -> Data {
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 612, height: 792))
        return renderer.pdfData { ctx in
            for index in 0..<document.pageCount {
                guard let page = document.page(at: index) else { continue }
                let rect = CGRect(origin: .zero, size: displaySize(page))
                ctx.beginPage(withBounds: rect, pageInfo: [:])
                drawPage(page, in: ctx.cgContext, size: rect.size)
                overlay(ctx.cgContext, rect, index)
            }
        }
    }

    /// Draws JPEG data so it is embedded as JPEG (keeps files small).
    static func drawJPEG(_ jpeg: Data, in rect: CGRect, context: CGContext) {
        guard let provider = CGDataProvider(data: jpeg as CFData),
              let image = CGImage(jpegDataProviderSource: provider, decode: nil,
                                  shouldInterpolate: true, intent: .defaultIntent)
        else { return }
        context.saveGState()
        context.translateBy(x: rect.minX, y: rect.maxY)
        context.scaleBy(x: 1, y: -1)
        context.draw(image, in: CGRect(origin: .zero, size: rect.size))
        context.restoreGState()
    }

    // MARK: Compress

    enum CompressionLevel: String, CaseIterable, Identifiable {
        case low = "Less compression"
        case recommended = "Recommended"
        case extreme = "Extreme compression"

        var id: String { rawValue }
        var detail: String {
            switch self {
            case .low: "High quality, less reduction"
            case .recommended: "Good quality, good reduction"
            case .extreme: "Smallest size, lower quality"
            }
        }
        var scale: CGFloat {
            switch self {
            case .low: 2.0
            case .recommended: 1.5
            case .extreme: 1.0
            }
        }
        var quality: CGFloat {
            switch self {
            case .low: 0.75
            case .recommended: 0.55
            case .extreme: 0.35
            }
        }
    }

    static func compress(_ document: PDFDocument, level: CompressionLevel,
                         progress: (Int, Int) -> Void = { _, _ in }) -> Data {
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 612, height: 792))
        return renderer.pdfData { ctx in
            for index in 0..<document.pageCount {
                progress(index + 1, document.pageCount)
                guard let page = document.page(at: index) else { continue }
                autoreleasepool {
                    let rect = CGRect(origin: .zero, size: displaySize(page))
                    ctx.beginPage(withBounds: rect, pageInfo: [:])
                    let image = renderImage(page, scale: level.scale)
                    if let jpeg = image.jpegData(compressionQuality: level.quality) {
                        drawJPEG(jpeg, in: rect, context: ctx.cgContext)
                    }
                }
            }
        }
    }

    // MARK: Images → PDF

    enum PageSize: String, CaseIterable, Identifiable {
        case fit = "Fit to image"
        case a4 = "A4"
        case letter = "US Letter"
        var id: String { rawValue }

        func size(for image: CGSize) -> CGSize {
            let portrait: CGSize
            switch self {
            case .fit: return image
            case .a4: portrait = CGSize(width: 595.2, height: 841.8)
            case .letter: portrait = CGSize(width: 612, height: 792)
            }
            return image.width > image.height ? CGSize(width: portrait.height, height: portrait.width) : portrait
        }
    }

    enum Margin: String, CaseIterable, Identifiable {
        case none = "No margin", small = "Small", large = "Big"
        var id: String { rawValue }
        var value: CGFloat {
            switch self {
            case .none: 0
            case .small: 20
            case .large: 40
            }
        }
    }

    static func imagesToPDF(_ images: [UIImage], pageSize: PageSize, margin: Margin, quality: CGFloat = 0.8) -> Data {
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 612, height: 792))
        return renderer.pdfData { ctx in
            for original in images {
                autoreleasepool {
                    let image = original.normalized(maxDimension: 2600)
                    // Pages sized to the image use 72 dpi equivalents capped to a sensible size.
                    var imageSize = image.size
                    if pageSize == .fit {
                        let factor = min(1, 1200 / max(imageSize.width, imageSize.height))
                        imageSize = CGSize(width: imageSize.width * factor, height: imageSize.height * factor)
                    }
                    let page = CGRect(origin: .zero, size: pageSize.size(for: imageSize))
                    ctx.beginPage(withBounds: page, pageInfo: [:])
                    let target = page.insetBy(dx: margin.value, dy: margin.value)
                    let fitted = AVMakeRect(aspectRatio: image.size, insideRect: target)
                    if let jpeg = image.jpegData(compressionQuality: quality) {
                        drawJPEG(jpeg, in: fitted, context: ctx.cgContext)
                    }
                }
            }
        }
    }

    // MARK: Watermark & page numbers

    enum WatermarkLayout: String, CaseIterable, Identifiable {
        case diagonal = "Diagonal", horizontal = "Horizontal", tiled = "Tiled"
        var id: String { rawValue }
    }

    static func watermark(_ document: PDFDocument, text: String, fontSize: CGFloat, color: UIColor,
                          opacity: CGFloat, layout: WatermarkLayout) -> Data {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: fontSize, weight: .bold),
            .foregroundColor: color.withAlphaComponent(opacity),
        ]
        let string = text as NSString
        let textSize = string.size(withAttributes: attributes)

        func draw(at center: CGPoint, angle: CGFloat, in context: CGContext) {
            context.saveGState()
            context.translateBy(x: center.x, y: center.y)
            context.rotate(by: angle)
            string.draw(at: CGPoint(x: -textSize.width / 2, y: -textSize.height / 2), withAttributes: attributes)
            context.restoreGState()
        }

        return stamp(document) { context, rect, _ in
            switch layout {
            case .horizontal:
                draw(at: CGPoint(x: rect.midX, y: rect.midY), angle: 0, in: context)
            case .diagonal:
                draw(at: CGPoint(x: rect.midX, y: rect.midY), angle: -atan2(rect.height, rect.width), in: context)
            case .tiled:
                let stepX = textSize.width + 60, stepY = textSize.height + 90
                var y: CGFloat = stepY / 2
                var row = 0
                while y < rect.height + stepY {
                    var x: CGFloat = row.isMultiple(of: 2) ? stepX / 2 : 0
                    while x < rect.width + stepX {
                        draw(at: CGPoint(x: x, y: y), angle: -.pi / 6, in: context)
                        x += stepX
                    }
                    y += stepY
                    row += 1
                }
            }
        }
    }

    enum NumberPosition: String, CaseIterable, Identifiable {
        case bottomCenter = "Bottom center", bottomRight = "Bottom right", bottomLeft = "Bottom left"
        case topCenter = "Top center", topRight = "Top right", topLeft = "Top left"
        var id: String { rawValue }
    }

    enum NumberFormat: String, CaseIterable, Identifiable {
        case number = "1", page = "Page 1", ofTotal = "1 / N", pageOfTotal = "Page 1 of N"
        var id: String { rawValue }
        func text(_ number: Int, total: Int) -> String {
            switch self {
            case .number: "\(number)"
            case .page: "Page \(number)"
            case .ofTotal: "\(number) / \(total)"
            case .pageOfTotal: "Page \(number) of \(total)"
            }
        }
    }

    static func addPageNumbers(_ document: PDFDocument, position: NumberPosition, format: NumberFormat,
                               startAt: Int, fontSize: CGFloat, skipFirst: Bool) -> Data {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: fontSize),
            .foregroundColor: UIColor.black,
        ]
        let numbered = document.pageCount - (skipFirst ? 1 : 0)
        let total = numbered + startAt - 1
        return stamp(document) { _, rect, index in
            if skipFirst && index == 0 { return }
            let number = index - (skipFirst ? 1 : 0) + startAt
            let text = format.text(number, total: total) as NSString
            let size = text.size(withAttributes: attributes)
            let margin = max(18, rect.width * 0.04)
            let x: CGFloat
            switch position {
            case .bottomLeft, .topLeft: x = margin
            case .bottomRight, .topRight: x = rect.width - margin - size.width
            case .bottomCenter, .topCenter: x = (rect.width - size.width) / 2
            }
            let isTop = position == .topLeft || position == .topCenter || position == .topRight
            let y = isTop ? margin : rect.height - margin - size.height
            text.draw(at: CGPoint(x: x, y: y), withAttributes: attributes)
        }
    }

    // MARK: Security

    static func protect(_ document: PDFDocument, password: String) throws -> Data {
        let url = TempFiles.newURL(ext: "pdf")
        defer { try? FileManager.default.removeItem(at: url) }
        let options: [PDFDocumentWriteOption: Any] = [
            .userPasswordOption: password,
            .ownerPasswordOption: password,
        ]
        guard document.write(to: url, withOptions: options) else { throw PDFToolError.writeFailed }
        return try Data(contentsOf: url)
    }

    /// Rebuilds the document page by page, which drops encryption and permission restrictions.
    static func unlocked(_ document: PDFDocument) throws -> Data {
        try data(of: copyPages(document, indices: Array(0..<document.pageCount)))
    }

    // MARK: Crop

    /// Insets are fractions (0...0.45) of the page's width/height, applied to every page.
    static func crop(_ document: PDFDocument, top: CGFloat, bottom: CGFloat, left: CGFloat, right: CGFloat) {
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { continue }
            let box = page.bounds(for: .mediaBox)
            let rect = CGRect(x: box.minX + box.width * left,
                              y: box.minY + box.height * bottom,
                              width: box.width * max(0.05, 1 - left - right),
                              height: box.height * max(0.05, 1 - top - bottom))
            page.setBounds(rect, for: .cropBox)
        }
    }
}

extension UIImage {
    /// Applies EXIF orientation and limits the pixel size.
    func normalized(maxDimension: CGFloat) -> UIImage {
        let pixelW = size.width * scale, pixelH = size.height * scale
        let factor = min(1, maxDimension / max(pixelW, pixelH, 1))
        let target = CGSize(width: (pixelW * factor).rounded(), height: (pixelH * factor).rounded())
        if imageOrientation == .up && factor == 1 && scale == 1 { return self }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: target))
        }
    }
}

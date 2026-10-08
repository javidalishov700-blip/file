import CoreText
import PDFKit
import UIKit
import Vision

struct RecognizedLine {
    let text: String
    /// Vision bounding box: normalized, origin at bottom-left.
    let box: CGRect
}

enum OCRService {
    static func recognize(_ image: UIImage) throws -> [RecognizedLine] {
        guard let cgImage = image.cgImage else { return [] }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: image.cgOrientation, options: [:])
        try handler.perform([request])
        return (request.results ?? []).compactMap { observation in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            return RecognizedLine(text: candidate.string, box: observation.boundingBox)
        }
    }

    static func text(of lines: [RecognizedLine]) -> String {
        // Vision returns lines roughly top-to-bottom; sort to be safe.
        lines.sorted { a, b in
            abs(a.box.midY - b.box.midY) < 0.01 ? a.box.minX < b.box.minX : a.box.midY > b.box.midY
        }
        .map(\.text)
        .joined(separator: "\n")
    }

    static func hasText(_ page: PDFPage) -> Bool {
        (page.string?.trimmingCharacters(in: .whitespacesAndNewlines).count ?? 0) > 15
    }

    /// Adds an invisible text layer to every page so the PDF becomes searchable and selectable.
    static func searchablePDF(_ document: PDFDocument, skipPagesWithText: Bool,
                              progress: @escaping (Int, Int) -> Void) throws -> Data {
        var linesPerPage: [Int: [RecognizedLine]] = [:]
        for index in 0..<document.pageCount {
            progress(index + 1, document.pageCount)
            guard let page = document.page(at: index) else { continue }
            if skipPagesWithText && hasText(page) { continue }
            try autoreleasepool {
                let image = PDFService.renderImage(page, scale: 2.5)
                linesPerPage[index] = try recognize(image)
            }
        }
        return PDFService.stamp(document) { context, rect, index in
            for line in linesPerPage[index] ?? [] {
                drawInvisible(line, pageRect: rect, context: context)
            }
        }
    }

    private static func drawInvisible(_ line: RecognizedLine, pageRect: CGRect, context: CGContext) {
        let rect = CGRect(x: line.box.minX * pageRect.width,
                          y: (1 - line.box.maxY) * pageRect.height,
                          width: line.box.width * pageRect.width,
                          height: line.box.height * pageRect.height)
        guard rect.width > 1, rect.height > 1 else { return }
        let font = UIFont.systemFont(ofSize: rect.height * 0.8)
        let attributed = NSAttributedString(string: line.text, attributes: [.font: font])
        let ctLine = CTLineCreateWithAttributedString(attributed)
        let width = CTLineGetTypographicBounds(ctLine, nil, nil, nil)
        guard width > 0 else { return }

        context.saveGState()
        context.setTextDrawingMode(.invisible)
        context.textMatrix = .identity
        // Flip locally so CoreText draws upright, then stretch the line to the recognized box.
        context.translateBy(x: rect.minX, y: rect.maxY)
        context.scaleBy(x: rect.width / CGFloat(width), y: -1)
        context.textPosition = CGPoint(x: 0, y: -font.descender)
        CTLineDraw(ctLine, context)
        context.restoreGState()
    }
}

/// Text extraction used by "PDF to Text" and "PDF to Word".
enum TextExtractor {
    /// Returns the text of every page; pages without a text layer are OCR'd when `useOCR` is on.
    static func pages(of document: PDFDocument, useOCR: Bool,
                      progress: @escaping (Int, Int) -> Void) throws -> [String] {
        var result: [String] = []
        for index in 0..<document.pageCount {
            progress(index + 1, document.pageCount)
            guard let page = document.page(at: index) else { result.append(""); continue }
            if OCRService.hasText(page) || !useOCR {
                result.append(page.string ?? "")
            } else {
                let lines = try autoreleasepool { try OCRService.recognize(PDFService.renderImage(page, scale: 2.5)) }
                result.append(OCRService.text(of: lines))
            }
        }
        return result
    }

    /// Joins wrapped lines back into paragraphs.
    static func paragraphs(_ pageText: String) -> [String] {
        let lines = pageText.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }
        let maxLength = lines.map(\.count).max() ?? 0
        var paragraphs: [String] = []
        var current = ""
        for line in lines {
            if line.isEmpty {
                if !current.isEmpty { paragraphs.append(current); current = "" }
                continue
            }
            if current.isEmpty {
                current = line
            } else if current.hasSuffix("-") {
                current = String(current.dropLast()) + line
            } else {
                current += " " + line
            }
            // A clearly short line ends the paragraph.
            if Double(line.count) < Double(maxLength) * 0.6 {
                paragraphs.append(current)
                current = ""
            }
        }
        if !current.isEmpty { paragraphs.append(current) }
        return paragraphs
    }

    static func markdown(title: String, pages: [String]) -> String {
        var output = "# \(title)\n"
        for (index, text) in pages.enumerated() {
            output += "\n## Page \(index + 1)\n\n"
            output += paragraphs(text).joined(separator: "\n\n") + "\n"
        }
        return output
    }

    static func plainText(pages: [String]) -> String {
        pages.joined(separator: "\n\n\u{0C}\n\n")
    }
}

extension UIImage {
    var cgOrientation: CGImagePropertyOrientation {
        switch imageOrientation {
        case .up: .up
        case .down: .down
        case .left: .left
        case .right: .right
        case .upMirrored: .upMirrored
        case .downMirrored: .downMirrored
        case .leftMirrored: .leftMirrored
        case .rightMirrored: .rightMirrored
        @unknown default: .up
        }
    }
}

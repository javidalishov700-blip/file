import SwiftUI

enum ToolCategory: String, CaseIterable, Identifiable {
    case scan = "Scan"
    case organize = "Organize PDF"
    case optimize = "Optimize PDF"
    case convertTo = "Convert to PDF"
    case convertFrom = "Convert from PDF"
    case edit = "Edit PDF"
    case security = "PDF Security"

    var id: String { rawValue }
}

enum Tool: String, CaseIterable, Identifiable, Hashable {
    case scan, ocr
    case merge, split, organize, rotate
    case compress, crop
    case imageToPDF, officeToPDF, webToPDF
    case pdfToImage, pdfToWord, pdfToText
    case edit, sign, watermark, pageNumbers
    case protect, unlock

    var id: String { rawValue }

    var title: String {
        switch self {
        case .scan: "Scan to PDF"
        case .ocr: "OCR PDF"
        case .merge: "Merge PDF"
        case .split: "Split PDF"
        case .organize: "Organize PDF"
        case .rotate: "Rotate PDF"
        case .compress: "Compress PDF"
        case .crop: "Crop PDF"
        case .imageToPDF: "JPG to PDF"
        case .officeToPDF: "Office to PDF"
        case .webToPDF: "HTML to PDF"
        case .pdfToImage: "PDF to JPG"
        case .pdfToWord: "PDF to Word"
        case .pdfToText: "PDF to Text"
        case .edit: "Edit PDF"
        case .sign: "Sign PDF"
        case .watermark: "Watermark"
        case .pageNumbers: "Page Numbers"
        case .protect: "Protect PDF"
        case .unlock: "Unlock PDF"
        }
    }

    var subtitle: String {
        switch self {
        case .scan: "Scan paper documents with your camera and save them as clean PDFs."
        case .ocr: "Turn scanned PDFs into searchable and selectable documents."
        case .merge: "Combine PDFs in the order you want into a single file."
        case .split: "Separate one page or a whole set into independent PDF files."
        case .organize: "Reorder, rotate or delete pages of your PDF."
        case .rotate: "Rotate all pages of your PDF the way you need them."
        case .compress: "Reduce file size while keeping good quality."
        case .crop: "Trim the margins of every page."
        case .imageToPDF: "Convert photos and images to PDF. Adjust page size and margins."
        case .officeToPDF: "Convert Word, Excel, PowerPoint, Pages, RTF and text files to PDF."
        case .webToPDF: "Convert any web page to PDF by pasting its URL."
        case .pdfToImage: "Convert each PDF page into a JPG or PNG image."
        case .pdfToWord: "Convert your PDF into an editable DOCX document."
        case .pdfToText: "Extract all text as plain text or Markdown."
        case .edit: "Add text, images, drawings and highlights to a PDF."
        case .sign: "Draw your signature and place it on any page."
        case .watermark: "Stamp text over your PDF. Choose size, color and transparency."
        case .pageNumbers: "Add page numbers. Choose position, format and size."
        case .protect: "Encrypt your PDF with a password."
        case .unlock: "Remove password security from a PDF you can open."
        }
    }

    var icon: String {
        switch self {
        case .scan: "doc.viewfinder"
        case .ocr: "text.viewfinder"
        case .merge: "arrow.triangle.merge"
        case .split: "scissors"
        case .organize: "square.grid.2x2"
        case .rotate: "rotate.right"
        case .compress: "arrow.down.right.and.arrow.up.left"
        case .crop: "crop"
        case .imageToPDF: "photo.on.rectangle"
        case .officeToPDF: "doc.richtext"
        case .webToPDF: "globe"
        case .pdfToImage: "photo"
        case .pdfToWord: "doc.text"
        case .pdfToText: "text.alignleft"
        case .edit: "square.and.pencil"
        case .sign: "signature"
        case .watermark: "drop.halffull"
        case .pageNumbers: "number"
        case .protect: "lock.shield"
        case .unlock: "lock.open"
        }
    }

    var color: Color {
        switch self {
        case .scan, .merge, .split, .organize: Color(red: 0.89, green: 0.42, blue: 0.31)
        case .ocr, .compress: Color(red: 0.49, green: 0.70, blue: 0.36)
        case .rotate, .crop, .edit, .watermark, .pageNumbers: Color(red: 0.63, green: 0.42, blue: 0.58)
        case .imageToPDF, .pdfToImage, .webToPDF: Color(red: 0.82, green: 0.70, blue: 0.20)
        case .officeToPDF, .pdfToWord, .sign, .protect, .unlock: Color(red: 0.31, green: 0.45, blue: 0.70)
        case .pdfToText: Color(red: 0.42, green: 0.36, blue: 0.86)
        }
    }

    var category: ToolCategory {
        switch self {
        case .scan, .ocr: .scan
        case .merge, .split, .organize, .rotate: .organize
        case .compress, .crop: .optimize
        case .imageToPDF, .officeToPDF, .webToPDF: .convertTo
        case .pdfToImage, .pdfToWord, .pdfToText: .convertFrom
        case .edit, .sign, .watermark, .pageNumbers: .edit
        case .protect, .unlock: .security
        }
    }
}

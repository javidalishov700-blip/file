import PDFKit
import UIKit

/// Debug-only helper for App Store screenshots: `-demoScreen <name>` opens a screen with
/// sample documents already loaded. Always nil in Release builds.
enum DemoMode {
    static var screen: String? {
        #if DEBUG
        return UserDefaults.standard.string(forKey: "demoScreen")
        #else
        return nil
        #endif
    }

    static var isActive: Bool { screen != nil }

    static let documents: [(name: String, title: String, lines: [String])] = [
        ("Invoice March", "INVOICE #2026-031", ["Design services ........ $1,200", "Development ........... $3,400", "Hosting (12 months) ...... $240", "", "Total due: $4,840"]),
        ("Rental Contract", "RESIDENTIAL LEASE AGREEMENT", ["This agreement is made between the Landlord and the Tenant.", "1. Term: 12 months starting November 1.", "2. Rent: payable on the first day of each month.", "3. Deposit: one month's rent."]),
        ("Lecture Notes - Physics", "Chapter 4: Energy", ["Kinetic energy: E = ½ m v²", "Potential energy: E = m g h", "Energy is conserved in a closed system.", "Power is the rate of doing work: P = W / t"]),
        ("Scan 2026-10-08 09.12", "RECEIPT", ["Coffee ........ 4.50", "Croissant ..... 3.20", "", "Thank you for your visit!"]),
    ]

    /// Writes the sample PDFs into My Files once and returns their URLs.
    @discardableResult
    static func seed(into store: FileStore) -> [URL] {
        documents.map { doc in
            let url = store.directory.appendingPathComponent(doc.name).appendingPathExtension("pdf")
            if !FileManager.default.fileExists(atPath: url.path) {
                try? samplePDF(title: doc.title, lines: doc.lines, pages: 3).write(to: url)
            }
            return url
        }
    }

    static func picked(_ urls: [URL]) -> [PickedPDF] {
        urls.compactMap { url in
            PDFDocument(url: url).map {
                PickedPDF(url: url, name: url.deletingPathExtension().lastPathComponent, document: $0)
            }
        }
    }

    static func samplePDF(title: String, lines: [String], pages: Int) -> Data {
        let bounds = CGRect(x: 0, y: 0, width: 595, height: 842)
        return UIGraphicsPDFRenderer(bounds: bounds).pdfData { ctx in
            for page in 1...pages {
                ctx.beginPage()
                UIColor(red: 0.90, green: 0.25, blue: 0.22, alpha: 1).setFill()
                ctx.fill(CGRect(x: 0, y: 0, width: bounds.width, height: 8))
                (title as NSString).draw(at: CGPoint(x: 56, y: 64), withAttributes: [
                    .font: UIFont.systemFont(ofSize: 24, weight: .bold), .foregroundColor: UIColor.black,
                ])
                var y: CGFloat = 120
                for line in lines {
                    (line as NSString).draw(at: CGPoint(x: 56, y: y), withAttributes: [
                        .font: UIFont.systemFont(ofSize: 14), .foregroundColor: UIColor.darkGray,
                    ])
                    y += 26
                }
                UIColor(white: 0.9, alpha: 1).setFill()
                for row in 0..<12 {
                    ctx.fill(CGRect(x: 56, y: y + 30 + CGFloat(row) * 28, width: CGFloat(300 + (row * 37) % 180), height: 10))
                }
                ("Page \(page)" as NSString).draw(at: CGPoint(x: 270, y: 800), withAttributes: [
                    .font: UIFont.systemFont(ofSize: 11), .foregroundColor: UIColor.gray,
                ])
            }
        }
    }
}

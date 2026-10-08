import Observation
import PDFKit
import PencilKit
import SwiftUI

struct OverlayItem: Identifiable {
    enum Kind {
        case text(String)
        case image(UIImage)
    }

    let id = UUID()
    var kind: Kind
    /// Center in page space, normalized to 0...1 with a top-left origin.
    var center: CGPoint
    /// Images: width as a fraction of the page width. Text: font size as a fraction of the page width.
    var size: CGFloat
    var color: Color = .black
}

@Observable
final class EditorModel {
    enum Mode { case select, draw }
    enum Pen: String, CaseIterable, Identifiable {
        case pen = "Pen", marker = "Highlighter", eraser = "Eraser"
        var id: String { rawValue }
    }

    let file: PickedPDF
    let document: PDFDocument
    var pageIndex = 0
    var mode: Mode = .select
    var pen: Pen = .pen
    var penColor: Color = .blue
    var items: [Int: [OverlayItem]] = [:]
    /// Drawings in page coordinates (points of the page's display size).
    var drawings: [Int: PKDrawing] = [:]
    var selectedID: UUID?
    @ObservationIgnored private var imageCache: [Int: UIImage] = [:]

    init(file: PickedPDF) {
        self.file = file
        self.document = file.fresh()
    }

    var pageCount: Int { document.pageCount }
    var page: PDFPage? { document.page(at: pageIndex) }
    var pageSize: CGSize { page.map(PDFService.displaySize) ?? CGSize(width: 612, height: 792) }

    var currentItems: [OverlayItem] {
        get { items[pageIndex] ?? [] }
        set { items[pageIndex] = newValue }
    }

    var selectedItem: OverlayItem? { currentItems.first { $0.id == selectedID } }

    func updateSelected(_ change: (inout OverlayItem) -> Void) {
        guard let index = currentItems.firstIndex(where: { $0.id == selectedID }) else { return }
        change(&currentItems[index])
    }

    /// Changes whenever the canvas must reload its drawing (page switch or "clear").
    var canvasKey: Int { pageIndex &* 10_000 &+ canvasRevision }
    private(set) var canvasRevision = 0

    func clearDrawing() {
        drawings[pageIndex] = PKDrawing()
        canvasRevision += 1
    }

    var hasChanges: Bool {
        items.values.contains { !$0.isEmpty } || drawings.values.contains { !$0.strokes.isEmpty }
    }

    func pageImage() -> UIImage? {
        if let cached = imageCache[pageIndex] { return cached }
        guard let page else { return nil }
        let image = PDFService.renderImage(page, scale: 2)
        imageCache[pageIndex] = image
        return image
    }

    func addText(_ text: String) {
        let item = OverlayItem(kind: .text(text), center: CGPoint(x: 0.5, y: 0.4), size: 0.045, color: .black)
        currentItems.append(item)
        selectedID = item.id
        mode = .select
    }

    func addImage(_ image: UIImage, center: CGPoint = CGPoint(x: 0.5, y: 0.5), width: CGFloat = 0.4) {
        let item = OverlayItem(kind: .image(image), center: center, size: width)
        currentItems.append(item)
        selectedID = item.id
        mode = .select
    }

    func deleteSelected() {
        currentItems.removeAll { $0.id == selectedID }
        selectedID = nil
    }

    func move(_ id: UUID, to center: CGPoint) {
        guard let index = currentItems.firstIndex(where: { $0.id == id }) else { return }
        currentItems[index].center = CGPoint(x: min(max(center.x, 0), 1), y: min(max(center.y, 0), 1))
    }

    func goTo(_ index: Int) {
        guard (0..<pageCount).contains(index) else { return }
        selectedID = nil
        pageIndex = index
    }

    /// Captures everything needed for export on the main thread, then builds the PDF off the main thread.
    func makeExportWork() -> ToolWork {
        let document = file.fresh()
        let items = self.items
        var drawingImages: [Int: UIImage] = [:]
        for (index, drawing) in drawings where !drawing.strokes.isEmpty {
            guard let page = self.document.page(at: index) else { continue }
            let size = PDFService.displaySize(page)
            UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
                drawingImages[index] = drawing.image(from: CGRect(origin: .zero, size: size), scale: 3)
            }
        }
        let resolved: [Int: [(OverlayItem, UIColor)]] = items.mapValues { list in list.map { ($0, UIColor($0.color)) } }
        let name = "\(file.name)_edited"
        let drawn = drawingImages

        return {
            let data = PDFService.stamp(document) { _, rect, index in
                drawn[index]?.draw(in: rect)
                for (item, color) in resolved[index] ?? [] {
                    let center = CGPoint(x: item.center.x * rect.width, y: item.center.y * rect.height)
                    switch item.kind {
                    case .text(let text):
                        let attributes: [NSAttributedString.Key: Any] = [
                            .font: UIFont.systemFont(ofSize: item.size * rect.width),
                            .foregroundColor: color,
                        ]
                        let string = text as NSString
                        let size = string.size(withAttributes: attributes)
                        string.draw(at: CGPoint(x: center.x - size.width / 2, y: center.y - size.height / 2),
                                    withAttributes: attributes)
                    case .image(let image):
                        let width = item.size * rect.width
                        let height = width * image.size.height / max(image.size.width, 1)
                        image.draw(in: CGRect(x: center.x - width / 2, y: center.y - height / 2,
                                              width: width, height: height))
                    }
                }
            }
            return [OutputFile(data: data, name: name, ext: "pdf")]
        }
    }
}

/// Remembers the user's last signature (stored privately, not in My Files).
enum SignatureStore {
    private static var url: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("signature.png")
    }

    static func load() -> UIImage? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    static func save(_ image: UIImage) {
        try? image.pngData()?.write(to: url, options: .atomic)
    }
}

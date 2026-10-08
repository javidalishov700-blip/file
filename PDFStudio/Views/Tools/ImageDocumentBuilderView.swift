import CoreImage
import CoreImage.CIFilterBuiltins
import PDFKit
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers
import VisionKit

/// Used by "Scan to PDF" (camera first) and "JPG to PDF" (photos first).
struct ImageDocumentBuilderView: View {
    let tool: Tool

    struct PageImage: Identifiable {
        let id = UUID()
        let image: UIImage
        let thumbnail: UIImage
    }

    @Environment(FileStore.self) private var store
    @State private var pages: [PageImage] = []
    @State private var showScanner = false
    @State private var didAutoLaunch = false
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var showFileImporter = false
    @State private var filter: ImageFilter = .original
    @State private var pageSize: PDFService.PageSize
    @State private var margin: PDFService.Margin = .none
    @State private var makeSearchable: Bool
    @State private var fileName: String
    @State private var runner = ToolRunner()

    private var canScan: Bool { VNDocumentCameraViewController.isSupported }

    init(tool: Tool) {
        self.tool = tool
        let isScan = tool == .scan
        _pageSize = State(initialValue: isScan ? .a4 : .fit)
        _makeSearchable = State(initialValue: isScan)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH.mm"
        _fileName = State(initialValue: "\(isScan ? "Scan" : "Images") \(formatter.string(from: Date()))")
    }

    var body: some View {
        List {
            Section { ToolHeader(tool: tool) }

            Section("Add pages") {
                if canScan {
                    Button { showScanner = true } label: { Label("Scan with camera", systemImage: "camera.viewfinder") }
                }
                PhotosPicker(selection: $photoItems, maxSelectionCount: nil, matching: .images) {
                    Label("Choose from Photos", systemImage: "photo.on.rectangle.angled")
                }
                Button { showFileImporter = true } label: { Label("Import image files", systemImage: "folder") }
            }

            if !pages.isEmpty {
                Section {
                    ForEach(Array(pages.enumerated()), id: \.element.id) { index, page in
                        HStack(spacing: 14) {
                            filter.preview(Image(uiImage: page.thumbnail).resizable())
                                .scaledToFit()
                                .frame(width: 56, height: 72)
                                .shadow(color: .black.opacity(0.15), radius: 2)
                            Text("Page \(index + 1)")
                        }
                    }
                    .onMove { pages.move(fromOffsets: $0, toOffset: $1) }
                    .onDelete { pages.remove(atOffsets: $0) }
                } header: {
                    Text("\(pages.count) page\(pages.count == 1 ? "" : "s")")
                }

                Section("Options") {
                    Picker("Color", selection: $filter) {
                        ForEach(ImageFilter.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Picker("Page size", selection: $pageSize) {
                        ForEach(PDFService.PageSize.allCases) { Text($0.rawValue).tag($0) }
                    }
                    Picker("Margin", selection: $margin) {
                        ForEach(PDFService.Margin.allCases) { Text($0.rawValue).tag($0) }
                    }
                    Toggle("Make text searchable (OCR)", isOn: $makeSearchable)
                    TextField("File name", text: $fileName)
                }

                Section {
                    Button(action: save) {
                        Text("Save as PDF").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(tool.color)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }
            }
        }
        .environment(\.editMode, .constant(pages.isEmpty ? .inactive : .active))
        .navigationTitle(tool.title)
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $showScanner) {
            DocumentScannerView { images in
                showScanner = false
                add(images)
            } onCancel: {
                showScanner = false
            }
            .ignoresSafeArea()
        }
        .onChange(of: photoItems) { _, items in
            guard !items.isEmpty else { return }
            Task {
                var images: [UIImage] = []
                for item in items {
                    if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                        images.append(image)
                    }
                }
                photoItems = []
                add(images)
            }
        }
        .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.image], allowsMultipleSelection: true) { result in
            guard case .success(let urls) = result else { return }
            let images = urls.compactMap { url -> UIImage? in
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                return (try? Data(contentsOf: url)).flatMap(UIImage.init(data:))
            }
            add(images)
        }
        .onAppear {
            if DemoMode.isActive && pages.isEmpty {
                didAutoLaunch = true
                add(DemoMode.documents.prefix(3).compactMap { doc in
                    PDFDocument(data: DemoMode.samplePDF(title: doc.title, lines: doc.lines, pages: 1))?
                        .page(at: 0).map { PDFService.renderImage($0, scale: 1.5) }
                })
            }
            if tool == .scan && canScan && pages.isEmpty && !didAutoLaunch {
                didAutoLaunch = true
                showScanner = true
            }
        }
        .toolRunner(runner)
    }

    private func add(_ images: [UIImage]) {
        for image in images {
            let normalized = image.normalized(maxDimension: 2600)
            let thumbnail = normalized.preparingThumbnail(of: CGSize(width: 160, height: 160 * normalized.size.height / max(normalized.size.width, 1))) ?? normalized
            pages.append(PageImage(image: normalized, thumbnail: thumbnail))
        }
    }

    private func save() {
        let images = pages.map(\.image)
        let (filter, pageSize, margin, searchable) = (self.filter, self.pageSize, self.margin, makeSearchable)
        let name = fileName.trimmingCharacters(in: .whitespaces).isEmpty ? "Scan" : fileName
        let progress = runner.progressReporter
        runner.run(store: store) {
            let processed = images.map { image in autoreleasepool { filter.apply(to: image) } }
            var data = PDFService.imagesToPDF(processed, pageSize: pageSize, margin: margin)
            if searchable, let document = PDFDocument(data: data) {
                data = try OCRService.searchablePDF(document, skipPagesWithText: false) { progress($0, $1) }
            }
            return [OutputFile(data: data, name: name, ext: "pdf")]
        }
    }
}

enum ImageFilter: String, CaseIterable, Identifiable {
    case original = "Original", grayscale = "Grayscale", blackWhite = "B&W"
    var id: String { rawValue }

    private static let context = CIContext()

    func apply(to image: UIImage) -> UIImage {
        guard self != .original, let cgImage = image.cgImage else { return image }
        let input = CIImage(cgImage: cgImage)
        let output: CIImage?
        switch self {
        case .original:
            output = input
        case .grayscale:
            let filter = CIFilter.photoEffectMono()
            filter.inputImage = input
            output = filter.outputImage
        case .blackWhite:
            let filter = CIFilter.colorControls()
            filter.inputImage = input
            filter.saturation = 0
            filter.contrast = 1.9
            filter.brightness = 0.12
            output = filter.outputImage
        }
        guard let output, let result = Self.context.createCGImage(output, from: input.extent) else { return image }
        return UIImage(cgImage: result)
    }

    @ViewBuilder
    func preview(_ image: Image) -> some View {
        switch self {
        case .original: image
        case .grayscale: image.grayscale(1)
        case .blackWhite: image.grayscale(1).contrast(1.9).brightness(0.08)
        }
    }
}

struct DocumentScannerView: UIViewControllerRepresentable {
    var onFinish: ([UIImage]) -> Void
    var onCancel: () -> Void

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: VNDocumentCameraViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let parent: DocumentScannerView
        init(parent: DocumentScannerView) { self.parent = parent }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController,
                                          didFinishWith scan: VNDocumentCameraScan) {
            parent.onFinish((0..<scan.pageCount).map { scan.imageOfPage(at: $0) })
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            parent.onCancel()
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
            parent.onCancel()
        }
    }
}

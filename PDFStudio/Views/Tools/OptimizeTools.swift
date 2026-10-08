import PDFKit
import SwiftUI

struct CompressToolView: View {
    @Environment(FileStore.self) private var store
    @State private var files: [PickedPDF] = []
    @State private var level: PDFService.CompressionLevel = .recommended

    var body: some View {
        PDFToolScreen(tool: .compress, allowsMultiple: true, actionTitle: "Compress PDF", files: $files) {
            Section("Compression level") {
                Picker("Level", selection: $level) {
                    ForEach(PDFService.CompressionLevel.allCases) { level in
                        VStack(alignment: .leading) {
                            Text(level.rawValue)
                            Text(level.detail).font(.caption).foregroundStyle(.secondary)
                        }
                        .tag(level)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }
        } work: { runner in
            let jobs = files.map { ($0.fresh(), $0.name, $0.fileSize) }
            let level = self.level
            let progress = runner.progressReporter
            return {
                try jobs.map { document, name, originalSize in
                    var data = PDFService.compress(document, level: level) { progress($0, $1) }
                    var note: String
                    if Int64(data.count) < originalSize {
                        let saved = 100 - Int(Double(data.count) / Double(max(originalSize, 1)) * 100)
                        note = "\(originalSize.formattedFileSize) → \(Int64(data.count).formattedFileSize) (−\(saved)%)"
                    } else {
                        // Already optimized: keep the original rather than producing a bigger file.
                        data = try PDFService.data(of: document)
                        note = "This PDF is already well optimized."
                    }
                    return OutputFile(data: data, name: "\(name)_compressed", ext: "pdf", note: note)
                }
            }
        }
        .onAppear {
            if DemoMode.isActive && files.isEmpty { files = DemoMode.picked([DemoMode.seed(into: store)[1]]) }
        }
    }
}

struct CropToolView: View {
    @State private var files: [PickedPDF] = []
    @State private var top = 0.05
    @State private var bottom = 0.05
    @State private var left = 0.05
    @State private var right = 0.05
    @State private var previewImage: UIImage?

    var body: some View {
        PDFToolScreen(tool: .crop, actionTitle: "Crop PDF", files: $files) {
            if let previewImage {
                Section("Preview") {
                    CropPreview(image: previewImage,
                                top: top, bottom: bottom, left: left, right: right)
                        .frame(height: 260)
                        .frame(maxWidth: .infinity)
                }
            }
            Section("Margins to remove") {
                MarginSlider(title: "Top", value: $top)
                MarginSlider(title: "Bottom", value: $bottom)
                MarginSlider(title: "Left", value: $left)
                MarginSlider(title: "Right", value: $right)
            }
            .task(id: files.first?.id) {
                previewImage = files.first?.document.page(at: 0).map { PDFService.thumbnail($0, maxDimension: 500) }
            }
        } work: { _ in
            guard let file = files.first else { throw PDFToolError.noPages }
            let document = file.fresh()
            let (t, b, l, r) = (CGFloat(top), CGFloat(bottom), CGFloat(left), CGFloat(right))
            let name = file.name
            return {
                PDFService.crop(document, top: t, bottom: b, left: l, right: r)
                return [try PDFService.pdf(document, name: "\(name)_cropped")]
            }
        }
    }
}

private struct MarginSlider: View {
    let title: String
    @Binding var value: Double

    var body: some View {
        HStack {
            Text(title).frame(width: 64, alignment: .leading)
            Slider(value: $value, in: 0...0.4)
            Text("\(Int(value * 100))%").monospacedDigit().frame(width: 44, alignment: .trailing)
        }
    }
}

private struct CropPreview: View {
    let image: UIImage
    let top: Double, bottom: Double, left: Double, right: Double

    var body: some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFit()
            .overlay {
                GeometryReader { geo in
                    let w = geo.size.width, h = geo.size.height
                    let rect = CGRect(x: w * left, y: h * top,
                                      width: w * max(0.05, 1 - left - right), height: h * max(0.05, 1 - top - bottom))
                    Path { path in
                        path.addRect(CGRect(origin: .zero, size: geo.size))
                        path.addRect(rect)
                    }
                    .fill(Color.black.opacity(0.45), style: FillStyle(eoFill: true))
                    Rectangle()
                        .stroke(Tool.crop.color, lineWidth: 2)
                        .frame(width: rect.width, height: rect.height)
                        .offset(x: rect.minX, y: rect.minY)
                }
            }
            .shadow(color: .black.opacity(0.15), radius: 3)
    }
}

struct OCRToolView: View {
    enum Output: String, CaseIterable, Identifiable {
        case searchablePDF = "Searchable PDF", text = "Text file"
        var id: String { rawValue }
    }

    @State private var files: [PickedPDF] = []
    @State private var output: Output = .searchablePDF
    @State private var skipTextPages = true

    var body: some View {
        PDFToolScreen(tool: .ocr, actionTitle: "Run OCR", files: $files) {
            Section {
                Picker("Output", selection: $output) {
                    ForEach(Output.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                Toggle("Skip pages that already have text", isOn: $skipTextPages)
            } header: {
                Text("Options")
            } footer: {
                Text("Text recognition runs privately on your device. Language is detected automatically.")
            }
        } work: { runner in
            guard let file = files.first else { throw PDFToolError.noPages }
            let document = file.fresh()
            let name = file.name
            let output = self.output
            let skip = skipTextPages
            let progress = runner.progressReporter
            return {
                switch output {
                case .searchablePDF:
                    let data = try OCRService.searchablePDF(document, skipPagesWithText: skip) { progress($0, $1) }
                    return [OutputFile(data: data, name: "\(name)_ocr", ext: "pdf")]
                case .text:
                    let pages = try TextExtractor.pages(of: document, useOCR: true) { progress($0, $1) }
                    return [OutputFile(data: Data(TextExtractor.plainText(pages: pages).utf8), name: name, ext: "txt")]
                }
            }
        }
    }
}

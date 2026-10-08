import PDFKit
import SwiftUI
import UniformTypeIdentifiers

struct PDFToImageView: View {
    enum Format: String, CaseIterable, Identifiable {
        case jpg = "JPG", png = "PNG"
        var id: String { rawValue }
    }
    enum Resolution: String, CaseIterable, Identifiable {
        case normal = "Normal", high = "High", maximum = "Maximum"
        var id: String { rawValue }
        var scale: CGFloat {
            switch self {
            case .normal: 1.5
            case .high: 2.5
            case .maximum: 4
            }
        }
    }

    @State private var files: [PickedPDF] = []
    @State private var format: Format = .jpg
    @State private var resolution: Resolution = .high

    var body: some View {
        PDFToolScreen(tool: .pdfToImage, actionTitle: "Convert to \(format.rawValue)", files: $files) {
            Section("Options") {
                Picker("Format", selection: $format) {
                    ForEach(Format.allCases) { Text($0.rawValue).tag($0) }
                }
                Picker("Quality", selection: $resolution) {
                    ForEach(Resolution.allCases) { Text($0.rawValue).tag($0) }
                }
            }
        } work: { runner in
            guard let file = files.first else { throw PDFToolError.noPages }
            let document = file.fresh()
            let name = file.name
            let format = self.format
            let scale = resolution.scale
            let progress = runner.progressReporter
            return {
                var outputs: [OutputFile] = []
                for index in 0..<document.pageCount {
                    progress(index + 1, document.pageCount)
                    guard let page = document.page(at: index) else { continue }
                    let data: Data? = autoreleasepool {
                        let image = PDFService.renderImage(page, scale: scale)
                        return format == .jpg ? image.jpegData(compressionQuality: 0.9) : image.pngData()
                    }
                    if let data {
                        outputs.append(OutputFile(data: data, name: "\(name)_page_\(index + 1)",
                                                  ext: format.rawValue.lowercased()))
                    }
                }
                return outputs
            }
        }
    }
}

struct PDFToWordView: View {
    @State private var files: [PickedPDF] = []
    @State private var useOCR = true

    var body: some View {
        PDFToolScreen(tool: .pdfToWord, actionTitle: "Convert to Word", files: $files) {
            Section {
                Toggle("Recognize text on scanned pages (OCR)", isOn: $useOCR)
            } footer: {
                Text("Creates a .docx file you can edit in Word, Pages or Google Docs. Text and paragraphs are kept; complex layouts are simplified.")
            }
        } work: { runner in
            guard let file = files.first else { throw PDFToolError.noPages }
            let document = file.fresh()
            let name = file.name
            let useOCR = self.useOCR
            let progress = runner.progressReporter
            return {
                let pages = try TextExtractor.pages(of: document, useOCR: useOCR) { progress($0, $1) }
                guard pages.contains(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
                    throw PDFToolError.message("No text was found in this PDF.")
                }
                let docx = DocxWriter.document(pages: pages.map(TextExtractor.paragraphs))
                return [OutputFile(data: docx, name: name, ext: "docx")]
            }
        }
    }
}

struct PDFToTextView: View {
    enum Format: String, CaseIterable, Identifiable {
        case txt = "Plain text (.txt)", markdown = "Markdown (.md)"
        var id: String { rawValue }
    }

    @State private var files: [PickedPDF] = []
    @State private var format: Format = .txt
    @State private var useOCR = true

    var body: some View {
        PDFToolScreen(tool: .pdfToText, actionTitle: "Extract text", files: $files) {
            Section("Options") {
                Picker("Format", selection: $format) {
                    ForEach(Format.allCases) { Text($0.rawValue).tag($0) }
                }
                Toggle("Recognize text on scanned pages (OCR)", isOn: $useOCR)
            }
        } work: { runner in
            guard let file = files.first else { throw PDFToolError.noPages }
            let document = file.fresh()
            let name = file.name
            let format = self.format
            let useOCR = self.useOCR
            let progress = runner.progressReporter
            return {
                let pages = try TextExtractor.pages(of: document, useOCR: useOCR) { progress($0, $1) }
                switch format {
                case .txt:
                    return [OutputFile(data: Data(TextExtractor.plainText(pages: pages).utf8), name: name, ext: "txt")]
                case .markdown:
                    let md = TextExtractor.markdown(title: name, pages: pages)
                    return [OutputFile(data: Data(md.utf8), name: name, ext: "md")]
                }
            }
        }
    }
}

// MARK: - Office / Web → PDF

struct OfficeToPDFView: View {
    static let types: [UTType] = {
        let extensions = ["doc", "docx", "xls", "xlsx", "ppt", "pptx", "pages", "numbers", "key", "rtf", "txt", "html", "htm", "csv"]
        var types = extensions.compactMap { UTType(filenameExtension: $0) }
        types += [.rtf, .plainText, .html, .commaSeparatedText]
        return types
    }()

    @Environment(FileStore.self) private var store
    @State private var urls: [URL] = []
    @State private var paper: WebPDFRenderer.Paper = .a4
    @State private var showImporter = false
    @State private var runner = ToolRunner()

    var body: some View {
        List {
            Section { ToolHeader(tool: .officeToPDF) }
            Section("Files") {
                ForEach(urls, id: \.self) { url in
                    HStack(spacing: 12) {
                        FileThumbnail(url: url)
                        Text(url.lastPathComponent).lineLimit(1)
                    }
                }
                .onDelete { urls.remove(atOffsets: $0) }
                Button { showImporter = true } label: {
                    Label(urls.isEmpty ? "Select files" : "Add more files", systemImage: "doc.badge.plus")
                }
            }
            if !urls.isEmpty {
                Section("Paper size") {
                    Picker("Paper", selection: $paper) {
                        ForEach(WebPDFRenderer.Paper.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
            }
            Section {
                Button(action: convert) {
                    Text("Convert to PDF").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .tint(Tool.officeToPDF.color)
                .disabled(urls.isEmpty)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
        }
        .navigationTitle(Tool.officeToPDF.title)
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(isPresented: $showImporter, allowedContentTypes: Self.types, allowsMultipleSelection: true) { result in
            switch result {
            case .success(let picked): urls += picked.compactMap { try? TempFiles.copy($0) }
            case .failure(let error): runner.fail(error)
            }
        }
        .toolRunner(runner)
    }

    private func convert() {
        let urls = self.urls
        let paper = self.paper
        runner.run(store: store) {
            var outputs: [OutputFile] = []
            for url in urls {
                let data = try await WebPDFRenderer.pdf(fromFile: url, paper: paper)
                outputs.append(OutputFile(data: data, name: url.deletingPathExtension().lastPathComponent, ext: "pdf"))
            }
            return outputs
        }
    }
}

struct WebToPDFView: View {
    @Environment(FileStore.self) private var store
    @State private var address = ""
    @State private var paper: WebPDFRenderer.Paper = .a4
    @State private var runner = ToolRunner()

    var body: some View {
        List {
            Section { ToolHeader(tool: .webToPDF) }
            Section("Web page") {
                TextField("https://example.com", text: $address)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.go)
                    .onSubmit(convert)
                Picker("Paper", selection: $paper) {
                    ForEach(WebPDFRenderer.Paper.allCases) { Text($0.rawValue).tag($0) }
                }
            }
            Section {
                Button(action: convert) {
                    Text("Convert to PDF").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .tint(Tool.webToPDF.color)
                .disabled(address.trimmingCharacters(in: .whitespaces).isEmpty)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
        }
        .navigationTitle(Tool.webToPDF.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolRunner(runner)
    }

    private func convert() {
        var text = address.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.lowercased().hasPrefix("http://") && !text.lowercased().hasPrefix("https://") {
            text = "https://" + text
        }
        guard let url = URL(string: text), let host = url.host(), host.contains(".") else {
            runner.fail(PDFToolError.message("Please enter a valid web address."))
            return
        }
        let paper = self.paper
        runner.run(store: store) {
            let data = try await WebPDFRenderer.pdf(fromWeb: url, paper: paper)
            return [OutputFile(data: data, name: host, ext: "pdf")]
        }
    }
}

import PDFKit
import SwiftUI

struct MergeToolView: View {
    @State private var files: [PickedPDF] = []

    var body: some View {
        PDFToolScreen(tool: .merge, allowsMultiple: true, minimumCount: 2,
                      actionTitle: "Merge PDF", files: $files) {
            EmptyView()
        } work: { _ in
            let documents = files.map { $0.fresh() }
            let name = (files.first?.name ?? "Document") + "_merged"
            return {
                [try PDFService.pdf(PDFService.merge(documents), name: name)]
            }
        }
    }
}

struct SplitToolView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case everyPage = "Every page"
        case ranges = "Custom ranges"
        case extract = "Extract pages"
        var id: String { rawValue }
    }

    @State private var files: [PickedPDF] = []
    @State private var mode: Mode = .ranges
    @State private var ranges = ""

    var body: some View {
        PDFToolScreen(tool: .split, actionTitle: "Split PDF", files: $files) {
            Section {
                Picker("Mode", selection: $mode) {
                    ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                if mode != .everyPage {
                    TextField("e.g. 1-3, 5, 8-10", text: $ranges)
                        .keyboardType(.numbersAndPunctuation)
                        .autocorrectionDisabled()
                }
            } header: {
                Text("Split mode")
            } footer: {
                switch mode {
                case .everyPage: Text("Every page becomes its own PDF.")
                case .ranges: Text("Each range becomes a separate PDF. The document has \(files.first?.pageCount ?? 0) pages.")
                case .extract: Text("All selected pages are combined into one new PDF.")
                }
            }
        } work: { _ in
            guard let file = files.first else { throw PDFToolError.noPages }
            let document = file.fresh()
            let count = document.pageCount
            let mode = self.mode
            let groups: [[Int]]
            if mode == .everyPage {
                groups = (0..<count).map { [$0] }
            } else {
                groups = try PDFService.parseRanges(ranges, pageCount: count)
            }
            let name = file.name
            return {
                if mode == .extract {
                    let pages = groups.flatMap { $0 }
                    return [try PDFService.pdf(PDFService.copyPages(document, indices: pages), name: "\(name)_extracted")]
                }
                return try groups.map { group in
                    let label = group.count == 1 ? "\(group[0] + 1)" : "\(group[0] + 1)-\(group[group.count - 1] + 1)"
                    return try PDFService.pdf(PDFService.copyPages(document, indices: group), name: "\(name)_\(label)")
                }
            }
        }
    }
}

struct RotateToolView: View {
    @State private var files: [PickedPDF] = []
    @State private var angle = 90

    var body: some View {
        PDFToolScreen(tool: .rotate, allowsMultiple: true, actionTitle: "Rotate PDF", files: $files) {
            Section("Rotation") {
                Picker("Angle", selection: $angle) {
                    Label("Right", systemImage: "rotate.right").tag(90)
                    Label("180°", systemImage: "arrow.up.arrow.down").tag(180)
                    Label("Left", systemImage: "rotate.left").tag(270)
                }
                .pickerStyle(.segmented)
            }
        } work: { _ in
            let jobs = files.map { ($0.fresh(), $0.name) }
            let angle = self.angle
            return {
                try jobs.map { document, name in
                    PDFService.rotate(document, by: angle)
                    return try PDFService.pdf(document, name: "\(name)_rotated")
                }
            }
        }
    }
}

// MARK: - Organize

struct OrganizeToolView: View {
    struct PageItem: Identifiable {
        let id = UUID()
        let source: Int
        var rotation: Int
        let thumbnail: UIImage
    }

    @Environment(FileStore.self) private var store
    @State private var file: PickedPDF?
    @State private var pages: [PageItem] = []
    @State private var showImporter = false
    @State private var runner = ToolRunner()

    var body: some View {
        List {
            Section { ToolHeader(tool: .organize) }
            if let file {
                Section {
                    PickedPDFRow(file: file)
                    Button("Choose another file") { showImporter = true }
                }
                Section {
                    ForEach($pages) { $page in
                        HStack(spacing: 14) {
                            Image(uiImage: page.thumbnail)
                                .resizable().scaledToFit()
                                .frame(width: 56, height: 72)
                                .rotationEffect(.degrees(Double(page.rotation)))
                                .shadow(color: .black.opacity(0.15), radius: 2)
                            Text("Page \(page.source + 1)")
                            Spacer()
                            Button {
                                page.rotation = (page.rotation + 90) % 360
                            } label: {
                                Image(systemName: "rotate.right")
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .onMove { pages.move(fromOffsets: $0, toOffset: $1) }
                    .onDelete { pages.remove(atOffsets: $0) }
                } header: {
                    Text("\(pages.count) pages")
                } footer: {
                    Text("Drag the handles to reorder, swipe to delete, tap ↻ to rotate.")
                }
                Section {
                    Button {
                        save(file)
                    } label: {
                        Text("Save PDF").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Tool.organize.color)
                    .disabled(pages.isEmpty)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }
            } else {
                Section {
                    Button { showImporter = true } label: { Label("Select PDF", systemImage: "doc.badge.plus") }
                }
            }
        }
        .environment(\.editMode, .constant(file == nil ? .inactive : .active))
        .navigationTitle(Tool.organize.title)
        .navigationBarTitleDisplayMode(.inline)
        .pdfImporter(isPresented: $showImporter) { picked in
            guard let first = picked.first else { return }
            file = first
            pages = (0..<first.pageCount).compactMap { index in
                guard let page = first.document.page(at: index) else { return nil }
                return PageItem(source: index, rotation: 0, thumbnail: PDFService.thumbnail(page, maxDimension: 160))
            }
        }
        .toolRunner(runner)
    }

    private func save(_ file: PickedPDF) {
        let document = file.fresh()
        let order = pages.map { ($0.source, $0.rotation) }
        let name = "\(file.name)_organized"
        runner.run(store: store) {
            let output = PDFDocument()
            for (source, rotation) in order {
                guard let page = document.page(at: source)?.copy() as? PDFPage else { continue }
                page.rotation = (page.rotation + rotation) % 360
                output.insert(page, at: output.pageCount)
            }
            return [try PDFService.pdf(output, name: name)]
        }
    }
}

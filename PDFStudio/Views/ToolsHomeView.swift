import SwiftUI

struct ToolsHomeView: View {
    @State private var search = ""
    @State private var path: [Tool] = []

    private let columns = [GridItem(.adaptive(minimum: 300), spacing: 14)]

    private var filtered: [Tool] {
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return Tool.allCases }
        return Tool.allCases.filter {
            $0.title.localizedCaseInsensitiveContains(query) || $0.subtitle.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if search.isEmpty { scanBanner }
                    ForEach(ToolCategory.allCases) { category in
                        let tools = filtered.filter { $0.category == category }
                        if !tools.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                Text(category.rawValue)
                                    .font(.title3.bold())
                                    .padding(.horizontal, 4)
                                LazyVGrid(columns: columns, spacing: 14) {
                                    ForEach(tools) { tool in
                                        NavigationLink(value: tool) { ToolCard(tool: tool) }
                                            .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                    }
                    if filtered.isEmpty {
                        ContentUnavailableView.search(text: search)
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("PDF Studio")
            .searchable(text: $search, prompt: "Search tools")
            .navigationDestination(for: Tool.self) { ToolDestination(tool: $0) }
        }
    }

    private var scanBanner: some View {
        Button { path.append(.scan) } label: {
            HStack(spacing: 16) {
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 30, weight: .semibold))
                    .frame(width: 60, height: 60)
                    .background(.white.opacity(0.2), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    Text("Scan a document").font(.title3.bold())
                    Text("Camera → clean, searchable PDF").font(.subheadline).opacity(0.9)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.headline)
            }
            .foregroundStyle(.white)
            .padding(18)
            .background(
                LinearGradient(colors: [Color(red: 0.90, green: 0.25, blue: 0.22), Color(red: 0.95, green: 0.45, blue: 0.30)],
                               startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: 22, style: .continuous)
            )
        }
        .buttonStyle(.plain)
    }
}

struct ToolCard: View {
    let tool: Tool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                ToolIcon(tool: tool, size: 44)
                Text(tool.title).font(.headline)
                Spacer(minLength: 0)
            }
            Text(tool.subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2, reservesSpace: true)
                .multilineTextAlignment(.leading)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color(.separator).opacity(0.4)))
        .contentShape(RoundedRectangle(cornerRadius: 18))
    }
}

struct ToolDestination: View {
    let tool: Tool

    var body: some View {
        switch tool {
        case .scan, .imageToPDF: ImageDocumentBuilderView(tool: tool)
        case .ocr: OCRToolView()
        case .merge: MergeToolView()
        case .split: SplitToolView()
        case .organize: OrganizeToolView()
        case .rotate: RotateToolView()
        case .compress: CompressToolView()
        case .crop: CropToolView()
        case .officeToPDF: OfficeToPDFView()
        case .webToPDF: WebToPDFView()
        case .pdfToImage: PDFToImageView()
        case .pdfToWord: PDFToWordView()
        case .pdfToText: PDFToTextView()
        case .edit, .sign: PDFEditorEntryView(tool: tool)
        case .watermark: WatermarkToolView()
        case .pageNumbers: PageNumbersToolView()
        case .protect: ProtectToolView()
        case .unlock: UnlockToolView()
        }
    }
}

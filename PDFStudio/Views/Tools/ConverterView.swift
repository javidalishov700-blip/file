import SwiftUI
import UniformTypeIdentifiers

/// "Convert Any File": pick anything, the app detects what it is and offers only the formats it can become.
struct ConverterView: View {
    var initialURLs: [URL] = []

    struct Item: Identifiable {
        let id = UUID()
        let url: URL
        let kind: FileKind
        var detail = ""
    }

    @Environment(FileStore.self) private var store
    @State private var items: [Item] = []
    @State private var target: TargetFormat?
    @State private var quality = 0.85
    @State private var combine = true
    @State private var showImporter = false
    @State private var didLoadInitial = false
    @State private var runner = ToolRunner()

    /// Formats every selected file can be converted to.
    private var targets: [TargetFormat] {
        guard let first = items.first else { return [] }
        var common = UniversalConverter.targets(for: first.kind, ext: first.url.pathExtension)
        for item in items.dropFirst() {
            let options = Set(UniversalConverter.targets(for: item.kind, ext: item.url.pathExtension))
            common = common.filter(options.contains)
        }
        return common
    }

    private var canCombine: Bool { items.count > 1 && target == .pdf && items.allSatisfy { $0.kind == .image } }

    var body: some View {
        List {
            Section { ToolHeader(tool: .convert) }

            Section {
                ForEach(items) { item in
                    HStack(spacing: 12) {
                        FileThumbnail(url: item.url)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.url.lastPathComponent).lineLimit(1)
                            Label(item.kind.title, systemImage: item.kind.icon)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(item.kind == .unsupported ? Color.red : Tool.convert.color)
                            if !item.detail.isEmpty {
                                Text(item.detail).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .onDelete { items.remove(atOffsets: $0) }
                Button { showImporter = true } label: {
                    Label(items.isEmpty ? "Choose files" : "Add more files", systemImage: "plus.circle.fill")
                }
            } header: {
                Text("Files")
            } footer: {
                if items.isEmpty {
                    Text("PDF, photos (JPG, PNG, HEIC…), Word, Excel, PowerPoint, Pages, text, web pages, videos and audio.")
                }
            }

            if !items.isEmpty {
                if targets.isEmpty {
                    Section {
                        Label(items.contains { $0.kind == .unsupported }
                              ? "This type of file can't be converted."
                              : "These files have no format in common. Convert them separately.",
                              systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Section("Convert to") {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 88), spacing: 10)], spacing: 10) {
                            ForEach(targets) { format in
                                FormatChip(format: format, isSelected: format == target) { target = format }
                            }
                        }
                        .padding(.vertical, 6)
                    }

                    if target?.usesQuality == true || (target == .pdf && items.allSatisfy { $0.kind == .image }) {
                        Section("Quality") {
                            LabeledSlider(title: "Quality", value: $quality, range: 0.3...1, format: { "\(Int($0 * 100))%" })
                        }
                    }
                    if canCombine {
                        Section {
                            Toggle("Combine into one PDF", isOn: $combine)
                        }
                    }

                    Section {
                        Button(action: convert) {
                            Text(target.map { "Convert to \($0.title)" } ?? "Choose a format")
                                .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Tool.convert.color)
                        .disabled(target == nil)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                    }
                }
            }
        }
        .readableWidth()
        .navigationTitle(Tool.convert.title)
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls): add(urls.compactMap { try? TempFiles.copy($0) })
            case .failure(let error): runner.fail(error)
            }
        }
        .onChange(of: targets) { _, available in
            if let target, available.contains(target) { return }
            target = available.first
        }
        .onAppear {
            guard !didLoadInitial else { return }
            didLoadInitial = true
            if !initialURLs.isEmpty {
                add(initialURLs)
            } else if DemoMode.isActive {
                add([DemoMode.seed(into: store)[1]])
            }
        }
        .toolRunner(runner)
    }

    private func add(_ urls: [URL]) {
        for url in urls {
            let item = Item(url: url, kind: UniversalConverter.detect(url))
            items.append(item)
            Task {
                let detail = await UniversalConverter.describe(url, kind: item.kind)
                if let index = items.firstIndex(where: { $0.id == item.id }) { items[index].detail = detail }
            }
        }
    }

    private func convert() {
        guard let target else { return }
        let jobs = items.map { ($0.url, $0.kind) }
        let quality = CGFloat(self.quality)
        let combineImages = canCombine && combine
        let progress = runner.progressReporter
        runner.run(store: store) {
            if combineImages {
                let name = (jobs.first?.0.deletingPathExtension().lastPathComponent ?? "Images") + "_combined"
                return [try UniversalConverter.combineImages(jobs.map(\.0), name: name, quality: quality)]
            }
            var outputs: [OutputFile] = []
            for (url, kind) in jobs {
                outputs += try await UniversalConverter.convert(url, kind: kind, to: target, quality: quality,
                                                                progress: { progress($0, $1) })
            }
            return outputs
        }
    }
}

private struct FormatChip: View {
    let format: TargetFormat
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: format.icon).font(.title3)
                Text(format.title).font(.footnote.weight(.semibold))
                Text(".\(format.ext)").font(.caption2).foregroundStyle(isSelected ? .white.opacity(0.8) : .secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 78)
            .foregroundStyle(isSelected ? .white : .primary)
            .background(isSelected ? AnyShapeStyle(Tool.convert.color.gradient) : AnyShapeStyle(Color(.tertiarySystemFill)),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

import SwiftUI

/// Shared layout for tools that take one or more PDFs, show some options and produce files.
struct PDFToolScreen<Options: View>: View {
    let tool: Tool
    var allowsMultiple = false
    var minimumCount = 1
    let actionTitle: String
    @Binding var files: [PickedPDF]
    let options: Options
    /// Validates the settings on the main thread and returns the work to run in the background.
    let makeWork: (ToolRunner) throws -> ToolWork

    @Environment(FileStore.self) private var store
    @State private var runner = ToolRunner()
    @State private var showImporter = false

    init(tool: Tool, allowsMultiple: Bool = false, minimumCount: Int = 1, actionTitle: String,
         files: Binding<[PickedPDF]>, @ViewBuilder options: () -> Options,
         work: @escaping (ToolRunner) throws -> ToolWork) {
        self.tool = tool
        self.allowsMultiple = allowsMultiple
        self.minimumCount = minimumCount
        self.actionTitle = actionTitle
        self._files = files
        self.options = options()
        self.makeWork = work
    }

    var body: some View {
        List {
            Section { ToolHeader(tool: tool) }

            Section {
                ForEach(files) { file in PickedPDFRow(file: file) }
                    .onDelete { files.remove(atOffsets: $0) }
                    .onMove { files.move(fromOffsets: $0, toOffset: $1) }
                Button {
                    showImporter = true
                } label: {
                    Label(files.isEmpty ? "Select PDF\(allowsMultiple ? " files" : "")"
                                        : (allowsMultiple ? "Add more files" : "Choose another file"),
                          systemImage: files.isEmpty ? "doc.badge.plus" : "plus.circle")
                }
            } header: {
                Text(allowsMultiple ? "Files" : "File")
            } footer: {
                if allowsMultiple && files.count > 1 {
                    Text("Tap Edit to change the order.")
                } else if files.count < minimumCount && minimumCount > 1 {
                    Text("Select at least \(minimumCount) files.")
                }
            }

            if !files.isEmpty { options }

            Section {
                Button {
                    do {
                        let work = try makeWork(runner)
                        runner.run(store: store, work)
                    } catch {
                        runner.fail(error)
                    }
                } label: {
                    Text(actionTitle)
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .tint(tool.color)
                .disabled(files.count < minimumCount)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
        }
        .navigationTitle(tool.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if allowsMultiple && files.count > 1 { EditButton() }
        }
        .pdfImporter(isPresented: $showImporter, allowsMultiple: allowsMultiple) { picked in
            if allowsMultiple { files.append(contentsOf: picked) } else { files = Array(picked.prefix(1)) }
        }
        .toolRunner(runner)
    }
}

import QuickLook
import SwiftUI

struct FilesView: View {
    @Environment(FileStore.self) private var store
    @State private var search = ""
    @State private var preview: URL?
    @State private var renaming: StoredFile?
    @State private var newName = ""
    @State private var showImporter = false

    private var filtered: [StoredFile] {
        guard !search.isEmpty else { return store.files }
        return store.files.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if store.files.isEmpty {
                    ContentUnavailableView {
                        Label("No files yet", systemImage: "folder")
                    } description: {
                        Text("Files you create with the tools are saved here. You can also find them in the Files app.")
                    } actions: {
                        Button("Import files") { showImporter = true }.buttonStyle(.borderedProminent)
                    }
                } else {
                    List {
                        ForEach(filtered) { file in
                            Button { preview = file.url } label: { row(file) }
                                .contextMenu { menu(file) }
                                .swipeActions {
                                    Button(role: .destructive) { store.delete([file]) } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                    ShareLink(item: file.url) { Label("Share", systemImage: "square.and.arrow.up") }
                                        .tint(.blue)
                                }
                        }
                    }
                    .searchable(text: $search, prompt: "Search files")
                    .refreshable { store.refresh() }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { BannerAdView() }
            .navigationTitle("My Files")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showImporter = true } label: { Image(systemName: "plus") }
                }
            }
            .quickLookPreview($preview, in: filtered.map(\.url))
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
                if case .success(let urls) = result { store.importFiles(urls) }
            }
            .alert("Rename", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
                TextField("Name", text: $newName)
                Button("Cancel", role: .cancel) {}
                Button("Save") {
                    if let renaming { try? store.rename(renaming, to: newName) }
                }
            }
            .onAppear { store.refresh() }
        }
    }

    private func row(_ file: StoredFile) -> some View {
        HStack(spacing: 12) {
            FileThumbnail(url: file.url, size: 48)
            VStack(alignment: .leading, spacing: 3) {
                Text(file.name).foregroundStyle(.primary).lineLimit(2)
                Text("\(file.modified.formatted(date: .abbreviated, time: .shortened)) · \(file.size.formattedFileSize)")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private func menu(_ file: StoredFile) -> some View {
        ShareLink(item: file.url) { Label("Share", systemImage: "square.and.arrow.up") }
        Button {
            newName = file.url.deletingPathExtension().lastPathComponent
            renaming = file
        } label: {
            Label("Rename", systemImage: "pencil")
        }
        Button(role: .destructive) { store.delete([file]) } label: { Label("Delete", systemImage: "trash") }
    }
}

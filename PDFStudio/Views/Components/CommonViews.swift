import PDFKit
import QuickLook
import QuickLookThumbnailing
import SwiftUI

struct ToolIcon: View {
    let tool: Tool
    var size: CGFloat = 44

    var body: some View {
        Image(systemName: tool.icon)
            .font(.system(size: size * 0.45, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(tool.color.gradient, in: RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
    }
}

struct ToolHeader: View {
    let tool: Tool

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ToolIcon(tool: tool, size: 52)
            Text(tool.subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
    }
}

struct FileThumbnail: View {
    let url: URL
    var size: CGFloat = 44
    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .shadow(color: .black.opacity(0.15), radius: 1, y: 1)
            } else {
                Image(systemName: "doc.fill")
                    .font(.system(size: size * 0.5))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .task(id: url) {
            let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: size, height: size),
                                                       scale: displayScale, representationTypes: .thumbnail)
            image = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request).uiImage
        }
    }
}

struct PickedPDFRow: View {
    let file: PickedPDF

    var body: some View {
        HStack(spacing: 12) {
            FileThumbnail(url: file.url)
            VStack(alignment: .leading, spacing: 2) {
                Text(file.name).font(.body).lineLimit(1)
                Text("\(file.pageCount) page\(file.pageCount == 1 ? "" : "s") · \(file.fileSize.formattedFileSize)")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if file.password != nil {
                Spacer()
                Image(systemName: "lock.fill").foregroundStyle(.secondary)
            }
        }
    }
}

struct ResultView: View {
    let urls: [URL]
    var notes: [URL: String] = [:]
    @Environment(\.dismiss) private var dismiss
    @State private var preview: URL?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(spacing: 10) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 54))
                            .foregroundStyle(.green)
                        Text(urls.count == 1 ? "Your file is ready" : "\(urls.count) files are ready")
                            .font(.title3.bold())
                        Text("Saved to My Files.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                Section {
                    ForEach(urls, id: \.self) { url in
                        Button { preview = url } label: {
                            HStack(spacing: 12) {
                                FileThumbnail(url: url, size: 48)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(url.lastPathComponent).foregroundStyle(.primary).lineLimit(2)
                                    Text(url.fileSize.formattedFileSize).font(.caption).foregroundStyle(.secondary)
                                    if let note = notes[url] {
                                        Text(note).font(.caption).foregroundStyle(.green)
                                    }
                                }
                                Spacer()
                                ShareLink(item: url) { Image(systemName: "square.and.arrow.up") }
                                    .buttonStyle(.borderless)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Done")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Close") { dismiss() } }
                ToolbarItem(placement: .bottomBar) {
                    ShareLink(items: urls) {
                        Label(urls.count == 1 ? "Share" : "Share All", systemImage: "square.and.arrow.up")
                    }
                }
            }
            .quickLookPreview($preview, in: urls)
        }
    }
}

extension URL {
    var fileSize: Int64 { Int64((try? resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
}

/// Text alert input helper used by several screens.
struct TextPrompt: Identifiable {
    let id = UUID()
    var title: String
    var text: String
    var onSave: (String) -> Void
}

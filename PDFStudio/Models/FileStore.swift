import Foundation
import Observation

struct StoredFile: Identifiable, Hashable {
    let url: URL
    let size: Int64
    let modified: Date

    var id: URL { url }
    var name: String { url.lastPathComponent }
    var ext: String { url.pathExtension.lowercased() }
}

/// Keeps every file the user creates in the app's Documents folder
/// (also visible in the Files app under "On My iPhone › PDF Studio").
@Observable
final class FileStore {
    private(set) var files: [StoredFile] = []

    let directory: URL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]

    init() { refresh() }

    var totalSize: Int64 { files.reduce(0) { $0 + $1.size } }

    func refresh() {
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey, .isDirectoryKey]
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])) ?? []
        files = urls.compactMap { url in
            let values = try? url.resourceValues(forKeys: Set(keys))
            if values?.isDirectory == true { return nil }
            return StoredFile(url: url,
                              size: Int64(values?.fileSize ?? 0),
                              modified: values?.contentModificationDate ?? .distantPast)
        }
        .sorted { $0.modified > $1.modified }
    }

    func uniqueURL(baseName: String, ext: String) -> URL {
        let clean = Self.sanitize(baseName)
        var url = directory.appendingPathComponent(clean).appendingPathExtension(ext)
        var counter = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = directory.appendingPathComponent("\(clean) (\(counter))").appendingPathExtension(ext)
            counter += 1
        }
        return url
    }

    @discardableResult
    func save(_ data: Data, baseName: String, ext: String) throws -> URL {
        let url = uniqueURL(baseName: baseName, ext: ext)
        try data.write(to: url, options: .atomic)
        refresh()
        return url
    }

    /// Copies external files (document picker, "Open in…") into My Files. Returns the number imported.
    @discardableResult
    func importFiles(_ urls: [URL]) -> Int {
        var count = 0
        for url in urls {
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            if url.deletingLastPathComponent().standardizedFileURL == directory.standardizedFileURL { continue }
            let dest = uniqueURL(baseName: url.deletingPathExtension().lastPathComponent, ext: url.pathExtension)
            if (try? FileManager.default.copyItem(at: url, to: dest)) != nil { count += 1 }
        }
        refresh()
        return count
    }

    func rename(_ file: StoredFile, to newName: String) throws {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let dest = uniqueURL(baseName: trimmed, ext: file.url.pathExtension)
        try FileManager.default.moveItem(at: file.url, to: dest)
        refresh()
    }

    func delete(_ files: [StoredFile]) {
        for file in files { try? FileManager.default.removeItem(at: file.url) }
        refresh()
    }

    func deleteAll() { delete(files) }

    static func sanitize(_ name: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\:?%*|\"<>")
        let cleaned = name.components(separatedBy: invalid).joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Document" : String(cleaned.prefix(120))
    }
}

enum TempFiles {
    /// Copies a picked file into a private temp folder so it stays readable after the picker closes.
    static func copy(_ url: URL) throws -> URL {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dest = dir.appendingPathComponent(url.lastPathComponent)
        try FileManager.default.copyItem(at: url, to: dest)
        return dest
    }

    static func newURL(ext: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension(ext)
    }
}

extension Int64 {
    var formattedFileSize: String { ByteCountFormatter.string(fromByteCount: self, countStyle: .file) }
}

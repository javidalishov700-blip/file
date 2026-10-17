import PDFKit
import SwiftUI
import UniformTypeIdentifiers

struct PickedPDF: Identifiable {
    let id = UUID()
    let url: URL
    let name: String
    let document: PDFDocument
    var password: String?

    var pageCount: Int { document.pageCount }
    var fileSize: Int64 {
        Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
    }

    /// A fresh, unmodified copy so tools can be run repeatedly with different settings.
    func fresh() -> PDFDocument {
        guard let copy = PDFDocument(url: url) else { return document }
        if let password { copy.unlock(withPassword: password) }
        return copy
    }
}

/// Document picker for PDFs that also asks for the password of protected files.
struct PDFImporterModifier: ViewModifier {
    @Binding var isPresented: Bool
    let allowsMultiple: Bool
    let onPicked: ([PickedPDF]) -> Void

    @State private var locked: [(url: URL, document: PDFDocument)] = []
    @State private var password = ""
    @State private var errorMessage: String?

    func body(content: Content) -> some View {
        content
            .fileImporter(isPresented: $isPresented, allowedContentTypes: [.pdf],
                          allowsMultipleSelection: allowsMultiple) { result in
                switch result {
                case .success(let urls): load(urls)
                case .failure(let error): errorMessage = error.localizedDescription
                }
            }
            .alert("Password required",
                   isPresented: Binding(get: { !locked.isEmpty }, set: { _ in })) {
                SecureField("Password", text: $password)
                Button("Open") { unlockFirst() }
                Button("Cancel", role: .cancel) {
                    if !locked.isEmpty { locked.removeFirst() }
                    password = ""
                }
            } message: {
                Text("\"\(locked.first?.url.lastPathComponent ?? "")\" is password protected.")
            }
            .background {
                Color.clear
                    .alert("Couldn't open file",
                           isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                        Button("OK", role: .cancel) {}
                    } message: {
                        Text(errorMessage ?? "")
                    }
            }
    }

    private func load(_ urls: [URL]) {
        var picked: [PickedPDF] = []
        for url in urls {
            do {
                let local = try TempFiles.copy(url)
                guard let document = PDFDocument(url: local) else {
                    throw PDFToolError.unreadable(url.lastPathComponent)
                }
                if document.isLocked {
                    locked.append((local, document))
                } else {
                    picked.append(PickedPDF(url: local, name: local.deletingPathExtension().lastPathComponent,
                                            document: document))
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
        if !picked.isEmpty { onPicked(picked) }
    }

    private func unlockFirst() {
        guard let item = locked.first else { return }
        locked.removeFirst()
        if item.document.unlock(withPassword: password) {
            onPicked([PickedPDF(url: item.url, name: item.url.deletingPathExtension().lastPathComponent,
                                document: item.document, password: password)])
        } else {
            errorMessage = "Wrong password for \"\(item.url.lastPathComponent)\"."
        }
        password = ""
    }
}

extension View {
    func pdfImporter(isPresented: Binding<Bool>, allowsMultiple: Bool = false,
                     onPicked: @escaping ([PickedPDF]) -> Void) -> some View {
        modifier(PDFImporterModifier(isPresented: isPresented, allowsMultiple: allowsMultiple, onPicked: onPicked))
    }
}

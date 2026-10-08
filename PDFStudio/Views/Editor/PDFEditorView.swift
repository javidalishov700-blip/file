import PDFKit
import PencilKit
import PhotosUI
import SwiftUI

/// Entry point for "Edit PDF" and "Sign PDF".
struct PDFEditorEntryView: View {
    let tool: Tool
    @Environment(FileStore.self) private var store
    @State private var model: EditorModel?
    @State private var showImporter = false
    @State private var didAutoOpen = false

    var body: some View {
        Group {
            if let model {
                PDFEditorView(model: model, signMode: tool == .sign) {
                    showImporter = true
                }
                .id(ObjectIdentifier(model))
            } else {
                List {
                    Section { ToolHeader(tool: tool) }
                    Section {
                        Button { showImporter = true } label: { Label("Select PDF", systemImage: "doc.badge.plus") }
                    }
                }
            }
        }
        .navigationTitle(tool.title)
        .navigationBarTitleDisplayMode(.inline)
        .pdfImporter(isPresented: $showImporter) { picked in
            if let first = picked.first { model = EditorModel(file: first) }
        }
        .onAppear {
            if model == nil && !didAutoOpen {
                didAutoOpen = true
                if DemoMode.isActive, let demo = DemoMode.picked([DemoMode.seed(into: store)[1]]).first {
                    let editor = EditorModel(file: demo)
                    editor.addText("Approved ✓")
                    editor.updateSelected { $0.color = .red; $0.center = CGPoint(x: 0.68, y: 0.62) }
                    editor.selectedID = nil
                    model = editor
                } else {
                    showImporter = true
                }
            }
        }
    }
}

struct PDFEditorView: View {
    @Bindable var model: EditorModel
    let signMode: Bool
    var onChangeFile: () -> Void

    @Environment(FileStore.self) private var store
    @State private var runner = ToolRunner()
    @State private var showSignaturePad = false
    @State private var showTextPrompt = false
    @State private var promptText = ""
    @State private var editingTextID: UUID?
    @State private var photoItem: PhotosPickerItem?
    @State private var didOpenSignature = false

    var body: some View {
        VStack(spacing: 0) {
            canvasArea
            Divider()
            VStack(spacing: 10) {
                if model.mode == .draw {
                    drawControls
                } else if let item = model.selectedItem {
                    selectionControls(item)
                }
                pageControls
                toolButtons
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
            .background(.bar)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Choose another PDF", systemImage: "doc", action: onChangeFile)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { runner.run(store: store, model.makeExportWork()) }
                    .bold()
                    .disabled(!model.hasChanges)
            }
        }
        .sheet(isPresented: $showSignaturePad) {
            SignaturePadView { image in
                model.addImage(image, center: CGPoint(x: 0.7, y: 0.85), width: 0.3)
            }
        }
        .alert(editingTextID == nil ? "Add text" : "Edit text", isPresented: $showTextPrompt) {
            TextField("Text", text: $promptText)
            Button("Cancel", role: .cancel) {}
            Button("OK", action: commitText)
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                    model.addImage(image.normalized(maxDimension: 1800))
                }
                photoItem = nil
            }
        }
        .onAppear {
            if signMode && !didOpenSignature && !DemoMode.isActive {
                didOpenSignature = true
                showSignaturePad = true
            }
        }
        .toolRunner(runner)
    }

    // MARK: Canvas

    private var canvasArea: some View {
        GeometryReader { geo in
            let pageSize = model.pageSize
            let available = CGSize(width: max(geo.size.width - 24, 1), height: max(geo.size.height - 24, 1))
            let scale = min(available.width / pageSize.width, available.height / pageSize.height)
            let fit = CGSize(width: pageSize.width * scale, height: pageSize.height * scale)

            ZStack(alignment: .topLeading) {
                Group {
                    if let image = model.pageImage() {
                        Image(uiImage: image).resizable()
                    } else {
                        Color.white
                    }
                }
                .frame(width: fit.width, height: fit.height)
                .onTapGesture { model.selectedID = nil }

                DrawingCanvas(drawing: Binding(get: { model.drawings[model.pageIndex] ?? PKDrawing() },
                                               set: { model.drawings[model.pageIndex] = $0 }),
                              key: model.canvasKey,
                              scale: scale,
                              isActive: model.mode == .draw,
                              tool: currentTool)
                    .frame(width: fit.width, height: fit.height)
                    .allowsHitTesting(model.mode == .draw)

                ForEach(model.currentItems) { item in
                    OverlayItemView(item: item, pageWidth: fit.width, isSelected: item.id == model.selectedID)
                        .position(x: item.center.x * fit.width, y: item.center.y * fit.height)
                        .onTapGesture(count: 2) { beginEditing(item) }
                        .onTapGesture { model.selectedID = item.id }
                        .gesture(
                            DragGesture(coordinateSpace: .named("page"))
                                .onChanged { value in
                                    model.selectedID = item.id
                                    model.move(item.id, to: CGPoint(x: value.location.x / fit.width,
                                                                    y: value.location.y / fit.height))
                                }
                        )
                        .allowsHitTesting(model.mode == .select)
                }
            }
            .frame(width: fit.width, height: fit.height)
            .coordinateSpace(name: "page")
            .clipped()
            .shadow(color: .black.opacity(0.2), radius: 6, y: 2)
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
        .background(Color(.secondarySystemBackground))
    }

    private var currentTool: PKTool {
        switch model.pen {
        case .pen: PKInkingTool(.pen, color: UIColor(model.penColor), width: 3)
        case .marker: PKInkingTool(.marker, color: UIColor(model.penColor).withAlphaComponent(0.5), width: 18)
        case .eraser: PKEraserTool(.vector)
        }
    }

    // MARK: Controls

    private var drawControls: some View {
        HStack(spacing: 12) {
            Picker("Pen", selection: $model.pen) {
                ForEach(EditorModel.Pen.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            ColorPicker("Color", selection: $model.penColor, supportsOpacity: false).labelsHidden()
            Button(role: .destructive) { model.clearDrawing() } label: { Image(systemName: "trash") }
        }
    }

    private func selectionControls(_ item: OverlayItem) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.up.left.and.arrow.down.right").foregroundStyle(.secondary)
            Slider(value: Binding(get: { Double(item.size) },
                                  set: { value in model.updateSelected { $0.size = CGFloat(value) } }),
                   in: item.isText ? 0.015...0.2 : 0.05...1)
            if item.isText {
                ColorPicker("Color", selection: Binding(get: { item.color },
                                                        set: { color in model.updateSelected { $0.color = color } }),
                            supportsOpacity: false)
                    .labelsHidden()
                Button { beginEditing(item) } label: { Image(systemName: "character.cursor.ibeam") }
            }
            Button(role: .destructive) { model.deleteSelected() } label: { Image(systemName: "trash") }
        }
    }

    private var pageControls: some View {
        HStack {
            Button { model.goTo(model.pageIndex - 1) } label: { Image(systemName: "chevron.left") }
                .disabled(model.pageIndex == 0)
            Spacer()
            Text("Page \(model.pageIndex + 1) of \(model.pageCount)")
                .font(.subheadline).monospacedDigit().foregroundStyle(.secondary)
            Spacer()
            Button { model.goTo(model.pageIndex + 1) } label: { Image(systemName: "chevron.right") }
                .disabled(model.pageIndex >= model.pageCount - 1)
        }
    }

    private var toolButtons: some View {
        HStack {
            EditorToolButton(title: "Text", icon: "textformat") {
                editingTextID = nil
                promptText = ""
                showTextPrompt = true
            }
            PhotosPicker(selection: $photoItem, matching: .images) {
                EditorToolLabel(title: "Image", icon: "photo")
            }
            .frame(maxWidth: .infinity)
            EditorToolButton(title: "Sign", icon: "signature") { showSignaturePad = true }
            EditorToolButton(title: model.mode == .draw ? "Done" : "Draw",
                             icon: model.mode == .draw ? "checkmark.circle.fill" : "pencil.tip",
                             highlighted: model.mode == .draw) {
                model.selectedID = nil
                model.mode = model.mode == .draw ? .select : .draw
            }
        }
    }

    private func beginEditing(_ item: OverlayItem) {
        guard case .text(let text) = item.kind else { return }
        model.selectedID = item.id
        editingTextID = item.id
        promptText = text
        showTextPrompt = true
    }

    private func commitText() {
        let text = promptText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        if let id = editingTextID {
            model.selectedID = id
            model.updateSelected { $0.kind = .text(text) }
        } else {
            model.addText(text)
        }
        editingTextID = nil
    }
}

extension OverlayItem {
    var isText: Bool {
        if case .text = kind { return true }
        return false
    }
}

private struct EditorToolLabel: View {
    let title: String
    let icon: String
    var highlighted = false

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon).font(.title3)
            Text(title).font(.caption2)
        }
        .foregroundStyle(highlighted ? Color.accentColor : Color.primary)
        .frame(maxWidth: .infinity)
    }
}

private struct EditorToolButton: View {
    let title: String
    let icon: String
    var highlighted = false
    let action: () -> Void

    var body: some View {
        Button(action: action) { EditorToolLabel(title: title, icon: icon, highlighted: highlighted) }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
    }
}

private struct OverlayItemView: View {
    let item: OverlayItem
    let pageWidth: CGFloat
    let isSelected: Bool

    var body: some View {
        content
            .padding(2)
            .overlay {
                if isSelected {
                    Rectangle().stroke(Color.accentColor, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                }
            }
            .contentShape(Rectangle())
    }

    @ViewBuilder private var content: some View {
        switch item.kind {
        case .text(let text):
            Text(text)
                .font(.system(size: max(item.size * pageWidth, 4)))
                .foregroundStyle(item.color)
                .fixedSize()
        case .image(let image):
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: item.size * pageWidth)
        }
    }
}

/// PencilKit canvas whose drawing is stored in page coordinates and displayed scaled.
struct DrawingCanvas: UIViewRepresentable {
    @Binding var drawing: PKDrawing
    let key: Int
    let scale: CGFloat
    let isActive: Bool
    let tool: PKTool

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.drawingPolicy = .anyInput
        canvas.overrideUserInterfaceStyle = .light
        canvas.isScrollEnabled = false
        canvas.delegate = context.coordinator
        return canvas
    }

    func updateUIView(_ canvas: PKCanvasView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        if coordinator.key != key || abs(coordinator.scale - scale) > 0.0001 {
            coordinator.key = key
            coordinator.scale = scale
            coordinator.isUpdating = true
            canvas.drawing = drawing.transformed(using: CGAffineTransform(scaleX: scale, y: scale))
            coordinator.isUpdating = false
        }
        canvas.tool = tool
        canvas.isUserInteractionEnabled = isActive
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        var parent: DrawingCanvas
        var key = Int.min
        var scale: CGFloat = 0
        var isUpdating = false

        init(parent: DrawingCanvas) { self.parent = parent }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            guard !isUpdating, scale > 0 else { return }
            parent.drawing = canvasView.drawing.transformed(using: CGAffineTransform(scaleX: 1 / scale, y: 1 / scale))
        }
    }
}

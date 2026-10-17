import PencilKit
import SwiftUI

struct SignaturePadView: View {
    var onDone: (UIImage) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var drawing = PKDrawing()
    @State private var ink: Ink = .black
    @State private var saved: UIImage? = SignatureStore.load()

    enum Ink: String, CaseIterable, Identifiable {
        case black, blue, red
        var id: String { rawValue }
        var color: UIColor {
            switch self {
            case .black: .black
            case .blue: UIColor(red: 0.05, green: 0.2, blue: 0.65, alpha: 1)
            case .red: UIColor(red: 0.75, green: 0.1, blue: 0.1, alpha: 1)
            }
        }
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                if let saved {
                    Text("Saved signature").font(.headline)
                    Button {
                        onDone(saved)
                        dismiss()
                    } label: {
                        Image(uiImage: saved).resizable().scaledToFit()
                            .frame(maxWidth: .infinity, maxHeight: 90)
                            .padding()
                            .background(Color.white, in: RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(.separator)))
                    }
                    .buttonStyle(.plain)
                    Text("Or draw a new one").font(.headline)
                } else {
                    Text("Draw your signature").font(.headline)
                }

                ZStack(alignment: .bottom) {
                    Color.white
                    Rectangle().fill(Color.gray.opacity(0.4)).frame(height: 1).padding(.horizontal, 24).padding(.bottom, 48)
                    SignatureCanvas(drawing: $drawing, ink: ink.color)
                }
                .frame(height: 240)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(.separator)))

                Picker("Ink", selection: $ink) {
                    ForEach(Ink.allCases) { ink in
                        Text(ink.rawValue.capitalized).tag(ink)
                    }
                }
                .pickerStyle(.segmented)

                Spacer()
            }
            .padding()
            .navigationTitle("Signature")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: finish).bold().disabled(drawing.strokes.isEmpty)
                }
                ToolbarItem(placement: .bottomBar) {
                    Button("Clear", role: .destructive) { drawing = PKDrawing() }.disabled(drawing.strokes.isEmpty)
                }
            }
        }
    }

    private func finish() {
        let bounds = drawing.bounds.insetBy(dx: -8, dy: -8)
        var image = UIImage()
        UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
            image = drawing.image(from: bounds, scale: 3)
        }
        SignatureStore.save(image)
        onDone(image)
        dismiss()
    }
}

private struct SignatureCanvas: UIViewRepresentable {
    @Binding var drawing: PKDrawing
    let ink: UIColor

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
        context.coordinator.parent = self
        canvas.tool = PKInkingTool(.pen, color: ink, width: 5)
        // Only push "Clear" down to the canvas; strokes flow up through the delegate.
        if drawing.strokes.isEmpty && !canvas.drawing.strokes.isEmpty { canvas.drawing = drawing }
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        var parent: SignatureCanvas
        init(parent: SignatureCanvas) { self.parent = parent }
        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            parent.drawing = canvasView.drawing
        }
    }
}

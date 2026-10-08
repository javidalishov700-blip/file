import PDFKit
import SwiftUI

struct WatermarkToolView: View {
    @State private var files: [PickedPDF] = []
    @State private var text = "CONFIDENTIAL"
    @State private var fontSize = 60.0
    @State private var opacity = 0.25
    @State private var color = Color.red
    @State private var layout: PDFService.WatermarkLayout = .diagonal

    var body: some View {
        PDFToolScreen(tool: .watermark, allowsMultiple: true, actionTitle: "Add watermark", files: $files) {
            Section("Text") {
                TextField("Watermark text", text: $text)
                ColorPicker("Color", selection: $color, supportsOpacity: false)
                LabeledSlider(title: "Size", value: $fontSize, range: 16...160, format: { "\(Int($0)) pt" })
                LabeledSlider(title: "Opacity", value: $opacity, range: 0.05...1, format: { "\(Int($0 * 100))%" })
            }
            Section("Position") {
                Picker("Layout", selection: $layout) {
                    ForEach(PDFService.WatermarkLayout.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
            }
        } work: { _ in
            let text = self.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { throw PDFToolError.message("Please enter the watermark text.") }
            let jobs = files.map { ($0.fresh(), $0.name) }
            let (size, opacity, layout) = (CGFloat(fontSize), CGFloat(self.opacity), self.layout)
            let uiColor = UIColor(color)
            return {
                jobs.map { document, name in
                    let data = PDFService.watermark(document, text: text, fontSize: size, color: uiColor,
                                                    opacity: opacity, layout: layout)
                    return OutputFile(data: data, name: "\(name)_watermarked", ext: "pdf")
                }
            }
        }
    }
}

struct PageNumbersToolView: View {
    @State private var files: [PickedPDF] = []
    @State private var position: PDFService.NumberPosition = .bottomCenter
    @State private var format: PDFService.NumberFormat = .number
    @State private var startAt = 1
    @State private var fontSize = 12.0
    @State private var skipFirst = false

    var body: some View {
        PDFToolScreen(tool: .pageNumbers, allowsMultiple: true, actionTitle: "Add page numbers", files: $files) {
            Section("Options") {
                Picker("Position", selection: $position) {
                    ForEach(PDFService.NumberPosition.allCases) { Text($0.rawValue).tag($0) }
                }
                Picker("Format", selection: $format) {
                    ForEach(PDFService.NumberFormat.allCases) { Text($0.rawValue).tag($0) }
                }
                Stepper("Start at \(startAt)", value: $startAt, in: 1...9999)
                LabeledSlider(title: "Size", value: $fontSize, range: 8...36, format: { "\(Int($0)) pt" })
                Toggle("Don't number the first page", isOn: $skipFirst)
            }
        } work: { _ in
            let jobs = files.map { ($0.fresh(), $0.name) }
            let (position, format, startAt, size, skipFirst) = (self.position, self.format, self.startAt, CGFloat(fontSize), self.skipFirst)
            return {
                jobs.map { document, name in
                    let data = PDFService.addPageNumbers(document, position: position, format: format,
                                                         startAt: startAt, fontSize: size, skipFirst: skipFirst)
                    return OutputFile(data: data, name: "\(name)_numbered", ext: "pdf")
                }
            }
        }
    }
}

struct ProtectToolView: View {
    @State private var files: [PickedPDF] = []
    @State private var password = ""
    @State private var confirmation = ""

    var body: some View {
        PDFToolScreen(tool: .protect, actionTitle: "Protect PDF", files: $files) {
            Section {
                SecureField("Password", text: $password)
                SecureField("Repeat password", text: $confirmation)
            } header: {
                Text("Set a password")
            } footer: {
                Text("The PDF is encrypted. Anyone opening it will need this password — don't forget it.")
            }
        } work: { _ in
            guard let file = files.first else { throw PDFToolError.noPages }
            guard password.count >= 4 else { throw PDFToolError.message("Use at least 4 characters.") }
            guard password == confirmation else { throw PDFToolError.message("The passwords don't match.") }
            let document = file.fresh()
            let password = self.password
            let name = file.name
            return {
                [OutputFile(data: try PDFService.protect(document, password: password), name: "\(name)_protected", ext: "pdf")]
            }
        }
    }
}

struct UnlockToolView: View {
    @State private var files: [PickedPDF] = []

    var body: some View {
        PDFToolScreen(tool: .unlock, allowsMultiple: true, actionTitle: "Unlock PDF", files: $files) {
            Section {
                EmptyView()
            } footer: {
                Text("You'll be asked for the password when you select a protected file. The new copy opens without a password and has no editing or printing restrictions.")
            }
        } work: { _ in
            let jobs = files.map { ($0.fresh(), $0.name, $0.document.isEncrypted) }
            return {
                try jobs.map { document, name, wasEncrypted in
                    OutputFile(data: try PDFService.unlocked(document), name: "\(name)_unlocked", ext: "pdf",
                               note: wasEncrypted ? "Password removed." : "This PDF wasn't protected.")
                }
            }
        }
    }
}

struct LabeledSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let format: (Double) -> String

    var body: some View {
        HStack {
            Text(title)
            Slider(value: $value, in: range)
            Text(format(value)).monospacedDigit().foregroundStyle(.secondary).frame(minWidth: 48, alignment: .trailing)
        }
    }
}

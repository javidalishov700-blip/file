import AVFoundation
import ImageIO
import PDFKit
import XCTest
@testable import PDFStudio

final class UniversalConverterTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("conv-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    // MARK: Sample files

    private func write(_ data: Data, _ name: String) throws -> URL {
        let url = dir.appendingPathComponent(name)
        try data.write(to: url)
        return url
    }

    private func samplePDF(_ name: String = "doc.pdf", pages: Int = 2) throws -> URL {
        let data = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 595, height: 842)).pdfData { ctx in
            for page in 1...pages {
                ctx.beginPage()
                ("Hello converter page \(page)" as NSString).draw(at: CGPoint(x: 60, y: 80),
                                                                  withAttributes: [.font: UIFont.systemFont(ofSize: 22)])
            }
        }
        return try write(data, name)
    }

    /// A PNG with a transparent half.
    private func samplePNG(_ name: String = "pic.png") throws -> URL {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let image = UIGraphicsImageRenderer(size: CGSize(width: 200, height: 100), format: format).image { ctx in
            UIColor.red.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
        }
        return try write(image.pngData()!, name)
    }

    private func sampleWAV() throws -> URL {
        let url = dir.appendingPathComponent("tone.wav")
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
        let file = try AVAudioFile(forWriting: url, settings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 44_100, AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false,
        ])
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 44_100)!
        buffer.frameLength = 44_100
        for i in 0..<44_100 { buffer.floatChannelData![0][i] = sin(Float(i) * 2 * .pi * 440 / 44_100) * 0.5 }
        try file.write(from: buffer)
        return url
    }

    /// A 1-second, 10 fps H.264 movie with changing colors.
    private func sampleMovie() async throws -> URL {
        let url = dir.appendingPathComponent("clip.mov")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 320, AVVideoHeightKey: 240,
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
            kCVPixelBufferWidthKey as String: 320, kCVPixelBufferHeightKey as String: 240,
        ])
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)
        for frame in 0..<10 {
            while !input.isReadyForMoreMediaData { try await Task.sleep(nanoseconds: 10_000_000) }
            var pixelBuffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &pixelBuffer)
            let buffer = pixelBuffer!
            CVPixelBufferLockBaseAddress(buffer, [])
            let ctx = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: 320, height: 240, bitsPerComponent: 8,
                                bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue)!
            ctx.setFillColor(UIColor(hue: CGFloat(frame) / 10, saturation: 1, brightness: 1, alpha: 1).cgColor)
            ctx.fill(CGRect(x: 0, y: 0, width: 320, height: 240))
            CVPixelBufferUnlockBaseAddress(buffer, [])
            adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: 10))
        }
        input.markAsFinished()
        await writer.finishWriting()
        XCTAssertEqual(writer.status, .completed)
        return url
    }

    private func contents(_ output: OutputFile) throws -> Data {
        if let url = output.fileURL { return try Data(contentsOf: url) }
        return output.data
    }

    private func imageType(_ data: Data) -> String? {
        CGImageSourceCreateWithData(data as CFData, nil).flatMap { CGImageSourceGetType($0) as String? }
    }

    // MARK: Detection

    func testDetection() throws {
        XCTAssertEqual(UniversalConverter.detect(try samplePDF()), .pdf)
        XCTAssertEqual(UniversalConverter.detect(try samplePNG()), .image)
        XCTAssertEqual(UniversalConverter.detect(try write(Data("x".utf8), "a.docx")), .office)
        XCTAssertEqual(UniversalConverter.detect(try write(Data("x".utf8), "a.xlsx")), .office)
        XCTAssertEqual(UniversalConverter.detect(try write(Data("x".utf8), "a.txt")), .text)
        XCTAssertEqual(UniversalConverter.detect(try write(Data("x".utf8), "a.csv")), .text)
        XCTAssertEqual(UniversalConverter.detect(try write(Data("x".utf8), "a.html")), .web)
        XCTAssertEqual(UniversalConverter.detect(try write(Data("x".utf8), "a.mp4")), .video)
        XCTAssertEqual(UniversalConverter.detect(try write(Data("x".utf8), "a.mp3")), .audio)
        // Wrong or missing extensions are detected from the content.
        let pdfData = try Data(contentsOf: try samplePDF())
        XCTAssertEqual(UniversalConverter.detect(try write(pdfData, "mystery")), .pdf)
        let pngData = try Data(contentsOf: try samplePNG())
        XCTAssertEqual(UniversalConverter.detect(try write(pngData, "photo.bin")), .image)
        XCTAssertEqual(UniversalConverter.detect(try write(Data([0, 1, 2, 3]), "blob.bin")), .unsupported)
    }

    func testTargetsExcludeOwnFormat() {
        XCTAssertFalse(UniversalConverter.targets(for: .image, ext: "jpeg").contains(.jpg))
        XCTAssertFalse(UniversalConverter.targets(for: .image, ext: "png").contains(.png))
        XCTAssertTrue(UniversalConverter.targets(for: .pdf).contains(.docx))
        XCTAssertTrue(UniversalConverter.targets(for: .unsupported).isEmpty)
    }

    // MARK: PDF →

    func testPDFToEverything() async throws {
        let url = try samplePDF(pages: 2)
        for target in UniversalConverter.targets(for: .pdf) {
            let outputs = try await UniversalConverter.convert(url, kind: .pdf, to: target)
            XCTAssertFalse(outputs.isEmpty, "\(target)")
            let data = try contents(outputs[0])
            XCTAssertGreaterThan(data.count, 20, "\(target)")
            XCTAssertEqual(outputs[0].ext, target.ext)
            switch target {
            case .jpg, .png, .tiff, .heic:
                XCTAssertEqual(outputs.count, 2, "one image per page")
                XCTAssertNotNil(imageType(data), "\(target) should be a readable image")
            case .docx:
                XCTAssertEqual(data.prefix(2), Data("PK".utf8))
            default:
                let text = String(decoding: data, as: UTF8.self)
                XCTAssertTrue(text.contains("Hello converter page 2"), "\(target) lost the text")
            }
        }
    }

    // MARK: Image →

    func testImageToEverything() async throws {
        let url = try samplePNG()
        for target in UniversalConverter.targets(for: .image, ext: "png") where target != .txt && target != .docx {
            let output = try await UniversalConverter.convert(url, kind: .image, to: target)[0]
            let data = try contents(output)
            if target == .pdf {
                XCTAssertEqual(PDFDocument(data: data)?.pageCount, 1)
            } else {
                XCTAssertNotNil(imageType(data), "\(target)")
            }
        }
    }

    func testJPGHasWhiteNotBlackBackground() async throws {
        let output = try await UniversalConverter.convert(try samplePNG(), kind: .image, to: .jpg)[0]
        let image = UIImage(data: output.data)!.cgImage!
        var pixel = [UInt8](repeating: 0, count: 4)
        let ctx = CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        // Sample the transparent right half.
        ctx.draw(image, in: CGRect(x: -150, y: -50, width: CGFloat(image.width), height: CGFloat(image.height)))
        XCTAssertGreaterThan(pixel[0], 230)
        XCTAssertGreaterThan(pixel[1], 230)
    }

    func testCombineImages() throws {
        let out = try UniversalConverter.combineImages([try samplePNG("a.png"), try samplePNG("b.png")], name: "x", quality: 0.8)
        XCTAssertEqual(PDFDocument(data: out.data)?.pageCount, 2)
    }

    // MARK: Text / web / office →

    func testTextToEverything() async throws {
        let url = try write(Data("Merhaba dünya — çğış\nSecond line".utf8), "note.txt")
        for target in UniversalConverter.targets(for: .text, ext: "txt") {
            let outputs = try await UniversalConverter.convert(url, kind: .text, to: target)
            let data = try contents(outputs[0])
            XCTAssertGreaterThan(data.count, 10, "\(target)")
            switch target {
            case .pdf:
                XCTAssertTrue((PDFDocument(data: data)?.string ?? "").contains("Merhaba"))
            case .html:
                XCTAssertTrue(String(decoding: data, as: UTF8.self).contains("<p>Merhaba dünya — çğış</p>"))
            case .rtf:
                let rtf = try NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.rtf],
                                                 documentAttributes: nil)
                XCTAssertTrue(rtf.string.contains("çğış"))
            default:
                break
            }
        }
    }

    func testWebPageToWord() async throws {
        let url = try write(Data("<html><body><h1>Menu</h1><p>Soup of the day</p></body></html>".utf8), "page.html")
        let out = try await UniversalConverter.convert(url, kind: .web, to: .docx)[0]
        XCTAssertEqual(out.data.prefix(2), Data("PK".utf8))
        let txt = try await UniversalConverter.convert(url, kind: .web, to: .txt)[0]
        XCTAssertTrue(String(decoding: txt.data, as: UTF8.self).contains("Soup of the day"))
    }

    // MARK: Audio / video →

    func testAudioConversions() async throws {
        let url = try sampleWAV()
        for target in UniversalConverter.targets(for: .audio, ext: "wav") {
            let output = try await UniversalConverter.convert(url, kind: .audio, to: target)[0]
            let file = try AVAudioFile(forReading: try XCTUnwrap(output.fileURL))
            XCTAssertEqual(Double(file.length) / file.fileFormat.sampleRate, 1.0, accuracy: 0.1, "\(target)")
        }
    }

    func testVideoConversions() async throws {
        let url = try await sampleMovie()
        let mp4 = try await UniversalConverter.convert(url, kind: .video, to: .mp4)[0]
        let duration = try await AVURLAsset(url: try XCTUnwrap(mp4.fileURL)).load(.duration).seconds
        XCTAssertEqual(duration, 1.0, accuracy: 0.2)

        let gif = try await UniversalConverter.convert(url, kind: .video, to: .gif)[0]
        let source = try XCTUnwrap(CGImageSourceCreateWithData(gif.data as CFData, nil))
        XCTAssertGreaterThan(CGImageSourceGetCount(source), 5, "animated GIF")

        do {
            _ = try await UniversalConverter.convert(url, kind: .video, to: .m4a)
            XCTFail("a silent video has no audio to extract")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("no sound"))
        }
    }
}

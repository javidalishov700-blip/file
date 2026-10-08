import UIKit
import WebKit

/// Converts web pages and documents WebKit can display (Word, Excel, PowerPoint, Pages,
/// Numbers, Keynote, RTF, TXT, HTML…) into paginated PDFs, fully on device.
@MainActor
final class WebPDFRenderer: NSObject, WKNavigationDelegate {
    enum Paper: String, CaseIterable, Identifiable {
        case a4 = "A4", letter = "US Letter"
        var id: String { rawValue }
        var rect: CGRect {
            switch self {
            case .a4: CGRect(x: 0, y: 0, width: 595.2, height: 841.8)
            case .letter: CGRect(x: 0, y: 0, width: 612, height: 792)
            }
        }
    }

    private var continuation: CheckedContinuation<Void, Error>?

    static func pdf(fromFile url: URL, paper: Paper) async throws -> Data {
        try await WebPDFRenderer().render(paper: paper, settle: 1.5) { webView in
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        }
    }

    static func pdf(fromWeb url: URL, paper: Paper) async throws -> Data {
        try await WebPDFRenderer().render(paper: paper, settle: 1.0) { webView in
            webView.load(URLRequest(url: url, timeoutInterval: 30))
        }
    }

    private func render(paper: Paper, settle: Double, load: (WKWebView) -> Void) async throws -> Data {
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: paper.rect.width, height: paper.rect.height))
        webView.navigationDelegate = self
        webView.alpha = 0.01
        webView.isUserInteractionEnabled = false
        // WebKit only lays out reliably when the view is in a window.
        let window = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first
        window?.insertSubview(webView, at: 0)
        defer {
            webView.stopLoading()
            webView.navigationDelegate = nil
            webView.removeFromSuperview()
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.continuation = continuation
            load(webView)
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 45_000_000_000)
                self?.finish(PDFToolError.message("Loading timed out."))
            }
        }
        try await Task.sleep(nanoseconds: UInt64(settle * 1_000_000_000))

        let data = paginate(webView, paper: paper)
        if data.count > 1000 { return data }
        // Fallback: single long page snapshot.
        return try await webView.pdf(configuration: WKPDFConfiguration())
    }

    private func paginate(_ webView: WKWebView, paper: Paper) -> Data {
        let renderer = PaperRenderer(paper: paper.rect, margin: 36)
        renderer.addPrintFormatter(webView.viewPrintFormatter(), startingAtPageAt: 0)
        let data = NSMutableData()
        UIGraphicsBeginPDFContextToData(data, paper.rect, nil)
        let pages = renderer.numberOfPages
        if pages > 0 {
            renderer.prepare(forDrawingPages: NSRange(location: 0, length: pages))
            let bounds = UIGraphicsGetPDFContextBounds()
            for index in 0..<pages {
                UIGraphicsBeginPDFPage()
                renderer.drawPage(at: index, in: bounds)
            }
        }
        UIGraphicsEndPDFContext()
        return pages > 0 ? data as Data : Data()
    }

    private func finish(_ error: Error?) {
        guard let continuation else { return }
        self.continuation = nil
        if let error { continuation.resume(throwing: error) } else { continuation.resume() }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        finish(nil)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finish(error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finish(error)
    }
}

private final class PaperRenderer: UIPrintPageRenderer {
    private let paper: CGRect
    private let margin: CGFloat

    init(paper: CGRect, margin: CGFloat) {
        self.paper = paper
        self.margin = margin
        super.init()
    }

    override var paperRect: CGRect { paper }
    override var printableRect: CGRect { paper.insetBy(dx: margin, dy: margin) }
}

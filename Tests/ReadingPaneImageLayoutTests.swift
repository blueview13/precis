import XCTest
import WebKit
@testable import Precis

/// Reading-pane document contract: the body fills the pane width (so the
/// SwiftUI header above it stays aligned with the article text) and images
/// render full-column with text flowing between them — no floats, no
/// centered measure.
@MainActor
final class ReadingPaneImageLayoutTests: XCTestCase {

    /// Inline SVG with a source width wider than the pane so `max-width: 100%`
    /// actually clamps it to the column — unlike a dead `src`, this loads.
    private let testImageSource = "data:image/svg+xml,%3Csvg%20xmlns='http://www.w3.org/2000/svg'%20" +
        "width='1200'%20height='600'%3E%3Crect%20width='1200'%20height='600'%20fill='%23c4d7ff'/%3E%3C/svg%3E"

    private func makeBody(imageCount: Int) -> String {
        let images = (0..<imageCount).map {
            "<p>Paragraph \($0) of the article body with some running text.</p>" +
            "<img src=\"\(testImageSource)\" alt=\"figure \(($0))\">"
        }
        return images.joined(separator: "\n") + "\n<p>Closing paragraph of the article body.</p>"
    }

    private func loadDocument(
        body: String,
        width: CGFloat = 900
    ) async throws -> WKWebView {
        let html = ReadingPaneView.document(body: body, fontSize: 15, scheme: .light, showImages: true)
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: width, height: 800))
        let navigation = ExpectationNavigation()
        webView.navigationDelegate = navigation
        webView.loadHTMLString(html, baseURL: nil)
        try await navigation.waitForLoad()
        return webView
    }

    // MARK: - Static document properties

    func testBodyFillsPaneWidthWithoutCenteredMeasure() {
        let html = ReadingPaneView.document(
            body: "<p>Body.</p>", fontSize: 15, scheme: .light, showImages: true
        )
        XCTAssertFalse(html.contains("max-width: 38em"), "the centered measure is gone")
        XCTAssertFalse(html.contains("margin: 0 auto"), "body must not center itself against the pane header")
        XCTAssertFalse(html.contains("precis-float"), "no float layout")
        XCTAssertFalse(html.contains("imageLayoutScript"), "no float-classification script")
    }

    func testImagesRenderAsFullWidthBlocks() {
        let html = ReadingPaneView.document(
            body: "<p>Body.</p>", fontSize: 15, scheme: .light, showImages: true
        )
        XCTAssertTrue(html.contains("img, video"), "image rule present")
        XCTAssertFalse(html.contains("margin: 1.2em auto"), "images must not auto-center")
        XCTAssertFalse(html.contains("float: right") || html.contains("float: left"), "no floats anywhere")
    }

    func testDisabledImagesDropMediaAndScript() {
        let html = ReadingPaneView.document(
            body: "<p>Body.</p>", fontSize: 15, scheme: .light, showImages: false
        )
        XCTAssertFalse(html.contains("data-precis-floated"), "no layout script for text-only mode")
        XCTAssertTrue(html.contains("display: none !important"))
    }

    // MARK: - Rendered layout (executed in WKWebView)

    func testBodySpansTheWebViewWidth() async throws {
        let webView = try await loadDocument(body: makeBody(imageCount: 3))
        defer { webView.navigationDelegate = nil }

        let bodyWidth = try await evaluate(
            "document.body.getBoundingClientRect().width", in: webView
        )
        let viewWidth = try await evaluate("document.documentElement.clientWidth", in: webView)
        XCTAssertGreaterThanOrEqual(
            Double(bodyWidth) ?? 0, (Double(viewWidth) ?? 0) - 8,
            "body should span the pane, not sit in a narrow centered column"
        )
    }

    func testAllImagesAreUnfloatedBlockElements() async throws {
        let webView = try await loadDocument(body: makeBody(imageCount: 4))
        defer { webView.navigationDelegate = nil }

        let floats = try await evaluate(
            "[...document.querySelectorAll('img')].map(i => getComputedStyle(i).float).join('|')",
            in: webView
        )
        XCTAssertEqual(floats, "none|none|none|none")

        let displays = try await evaluate(
            "[...document.querySelectorAll('img')].map(i => getComputedStyle(i).display).join('|')",
            in: webView
        )
        XCTAssertEqual(displays, "block|block|block|block")
    }

    func testImagesStackWithTextBetweenThem() async throws {
        // Each image is followed by a paragraph: images render sequentially
        // down the column (y strictly increasing, no side-by-side overlap).
        let webView = try await loadDocument(body: makeBody(imageCount: 3))
        defer { webView.navigationDelegate = nil }

        let rects = try await evaluate(
            "JSON.stringify([...document.querySelectorAll('img')].map(i => { " +
            "const r = i.getBoundingClientRect(); return { x: Math.round(r.x), y: Math.round(r.y), w: Math.round(r.width) }; }))",
            in: webView
        )
        struct ImgRect: Decodable { let x: Int; let y: Int; let w: Int }
        let images = try JSONDecoder().decode([ImgRect].self, from: Data(rects.utf8))
        XCTAssertEqual(images.count, 3)
        XCTAssertEqual(images[0].x, images[1].x, "images share the same left edge (text column)")
        XCTAssertGreaterThan(images[1].y, images[0].y, "second image renders below the first")
        XCTAssertGreaterThan(images[2].y, images[1].y, "third image renders below the second")
        let viewWidth = Double(try await evaluate("document.documentElement.clientWidth", in: webView)) ?? 0
        XCTAssertGreaterThan(Double(images[0].w) ?? 0, viewWidth * 0.9, "images span most of the column")
    }

    // MARK: - Helpers

    private func evaluate(_ expression: String, in webView: WKWebView) async throws -> String {
        let value = try await webView.evaluateJavaScript(expression)
        if let number = value as? Double { return String(number) }
        if let string = value as? String { return string }
        throw NSError(domain: "ReadingPaneImageLayoutTests", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "JavaScript did not return a scalar: \(String(describing: value))"
        ])
    }
}

/// One-shot navigation waiter — WKWebView's load is async and the layout
/// must have settled before assertions read the DOM.
private final class ExpectationNavigation: NSObject, WKNavigationDelegate {
    private var continuation: CheckedContinuation<Void, Error>?

    func waitForLoad() async throws {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        continuation?.resume()
        continuation = nil
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        continuation?.resume(throwing: error)
        continuation = nil
    }
}

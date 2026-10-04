import AppKit
import SwiftUI
import XCTest
import WebKit
@testable import Precis

/// Reading-pane document contract: the article renders in one centred column
/// whose width matches the SwiftUI header above it (so the pane reads as a
/// single centralised block) and images are capped at that same column width
/// with text flowing between them — no floats, no edge-to-edge measure.
@MainActor
final class ReadingPaneImageLayoutTests: XCTestCase {

    /// Inline SVG with a source width wider than the column so `max-width: 100%`
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
        width: CGFloat = 900,
        contentWidth: Double = 750
    ) async throws -> WKWebView {
        let html = ReadingPaneView.document(
            body: body, fontSize: 15, scheme: .light, showImages: true, contentWidth: contentWidth
        )
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: width, height: 800))
        let navigation = ExpectationNavigation()
        webView.navigationDelegate = navigation
        webView.loadHTMLString(html, baseURL: nil)
        try await navigation.waitForLoad()
        return webView
    }

    // MARK: - Static document properties

    func testDocumentUsesCenteredColumnWithDefaultWidth() {
        let html = ReadingPaneView.document(
            body: "<p>Body.</p>", fontSize: 15, scheme: .light, showImages: true
        )
        XCTAssertTrue(html.contains("max-width: 750px"), "default content width is 750px")
        XCTAssertTrue(html.contains("margin: 0 auto"), "the column centres itself in the pane")
        XCTAssertTrue(html.contains("class=\"precis-column\""), "the body sits in the centered column")
        XCTAssertFalse(html.contains("precis-float"), "no float layout")
        XCTAssertFalse(html.contains("imageLayoutScript"), "no float-classification script")
    }

    func testContentWidthIsConfigurable() {
        let html = ReadingPaneView.document(
            body: "<p>Body.</p>", fontSize: 15, scheme: .light, showImages: true, contentWidth: 500
        )
        XCTAssertTrue(html.contains("max-width: 500px"), "the setting drives the column width")
        XCTAssertFalse(html.contains("max-width: 750px"), "the default is not baked in twice")
    }

    func testImagesRenderAsColumnWidthBlocks() {
        let html = ReadingPaneView.document(
            body: "<p>Body.</p>", fontSize: 15, scheme: .light, showImages: true
        )
        XCTAssertTrue(html.contains("img, video"), "image rule present")
        XCTAssertTrue(html.contains("max-width: 100%"), "images never exceed the text column")
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

    func testColumnIsCenteredAtTheConfiguredWidth() async throws {
        // A 900pt pane with the 750px default: the column fills its measure
        // and the leftover space is split evenly on either side.
        let webView = try await loadDocument(body: makeBody(imageCount: 3))
        defer { webView.navigationDelegate = nil }

        let metrics = try await json(
            "JSON.stringify((() => { const c = document.querySelector('.precis-column').getBoundingClientRect(); " +
            "return { width: Math.round(c.width), left: Math.round(c.left), " +
            "right: Math.round(document.documentElement.clientWidth - c.right) }; })())",
            in: webView
        )
        let width = try XCTUnwrap(metrics["width"])
        let left = try XCTUnwrap(metrics["left"])
        let right = try XCTUnwrap(metrics["right"])
        XCTAssertEqual(width, 750, "column honours the configured width")
        XCTAssertEqual(left, right, "column is centered in the pane")
        XCTAssertGreaterThan(left, 0, "column does not touch the pane edge")
    }

    func testNarrowPaneShrinksTheColumnToFit() async throws {
        // When the pane is narrower than the configured width the column
        // simply fills the pane instead of overflowing it.
        let webView = try await loadDocument(body: makeBody(imageCount: 2), width: 520, contentWidth: 1200)
        defer { webView.navigationDelegate = nil }

        let metrics = try await json(
            "JSON.stringify((() => { const c = document.querySelector('.precis-column').getBoundingClientRect(); " +
            "return { width: Math.round(c.width), view: document.documentElement.clientWidth }; })())",
            in: webView
        )
        let width = try XCTUnwrap(metrics["width"])
        let view = try XCTUnwrap(metrics["view"])
        XCTAssertLessThanOrEqual(width, view + 1, "column never overflows a narrow pane")
        XCTAssertEqual(width, 520, "column fills the narrow pane")
    }

    func testImagesMatchTheTextColumnWidth() async throws {
        let webView = try await loadDocument(body: makeBody(imageCount: 3))
        defer { webView.navigationDelegate = nil }

        let widths = try await json(
            "JSON.stringify((() => { const img = document.querySelector('img').getBoundingClientRect().width; " +
            "const p = document.querySelector('p').getBoundingClientRect().width; " +
            "const c = document.querySelector('.precis-column').getBoundingClientRect().width; " +
            "return { img: Math.round(img), p: Math.round(p), column: Math.round(c) }; })())",
            in: webView
        )
        // A wide picture is clamped to the column and so is exactly as wide
        // as the running text beside it.
        let image = try XCTUnwrap(widths["img"])
        let paragraph = try XCTUnwrap(widths["p"])
        let column = try XCTUnwrap(widths["column"])
        XCTAssertEqual(image, paragraph, "image width matches the text measure")
        XCTAssertLessThan(image, column, "column keeps its side padding")
    }

    func testPaneHostsTheArticleColumnCentredAtTheConfiguredWidth() async throws {
        // End-to-end check of the SwiftUI side: hosting the real pane at a
        // 1000pt width must leave the article web view 750pt wide, with the
        // leftover space split evenly (32pt pane padding + 93pt each side).
        //
        // The pane reads its width from @AppStorage, so the machine's real
        // preference is pinned for the duration and restored afterwards.
        let key = "readingContentWidth"
        let saved = UserDefaults.standard.object(forKey: key)
        UserDefaults.standard.set(750.0, forKey: key)
        defer {
            if let saved {
                UserDefaults.standard.set(saved, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }

        let pane = ReadingPaneView(item: nil, emptyMessage: "Nothing selected.")
        let hosting = NSHostingView(rootView: pane)
        hosting.frame = NSRect(x: 0, y: 0, width: 1000, height: 700)
        let window = NSWindow(
            contentRect: hosting.frame,
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView = hosting
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }

        var webView: WKWebView?
        for _ in 0..<40 {
            hosting.layoutSubtreeIfNeeded()
            webView = hosting.firstDescendant(ofType: WKWebView.self)
            if webView != nil { break }
            try await Task.sleep(for: .milliseconds(50))
        }

        let article = try XCTUnwrap(webView, "the pane hosts an article web view")
        let frame = article.convert(article.bounds, to: hosting)
        XCTAssertEqual(frame.width, 750, accuracy: 1, "article column uses the configured width")
        XCTAssertEqual(frame.minX, 125, accuracy: 1, "column is centred in the pane")
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
        XCTAssertGreaterThan(
            images[0].w, 600,
            "a wide image spans the reading column rather than shrinking to a thumbnail"
        )
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

    private func json(_ expression: String, in webView: WKWebView) async throws -> [String: Int] {
        let raw = try await evaluate(expression, in: webView)
        return (try JSONSerialization.jsonObject(with: Data(raw.utf8))) as? [String: Int] ?? [:]
    }
}

private extension NSView {
    /// Depth-first search for the first descendant of the requested type.
    func firstDescendant<T: NSView>(ofType type: T.Type) -> T? {
        for subview in subviews {
            if let match = subview as? T { return match }
            if let match = subview.firstDescendant(ofType: type) { return match }
        }
        return nil
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

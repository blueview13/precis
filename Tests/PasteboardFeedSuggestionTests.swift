import AppKit
import XCTest
@testable import Precis

final class PasteboardFeedSuggestionTests: XCTestCase {
    func testCopiedWebURLIsSuggested() async {
        let pasteboard = makePasteboard()
        pasteboard.setString("https://example.com/feed.xml", forType: .string)

        let suggestion = await PasteboardFeedSuggestion.copiedURL(from: pasteboard)

        XCTAssertEqual(suggestion, "https://example.com/feed.xml")
    }

    func testPasteboardWithoutAURLSuggestsNothing() async {
        let pasteboard = makePasteboard()
        pasteboard.setString("just some thoughts, no link", forType: .string)

        let suggestion = await PasteboardFeedSuggestion.copiedURL(from: pasteboard)

        XCTAssertNil(suggestion)
    }

    func testNonWebSchemesAreNeverOffered() async {
        // Detection reports these too, but neither can become a feed.
        XCTAssertNil(PasteboardFeedSuggestion.candidate(from: "mailto:someone@example.com"))
        XCTAssertNil(PasteboardFeedSuggestion.candidate(from: "javascript:alert(1)"))
        XCTAssertNil(PasteboardFeedSuggestion.candidate(from: "file:///Users/someone/feed.xml"))
    }

    func testHTTPAndHTTPSPassThrough() {
        XCTAssertEqual(PasteboardFeedSuggestion.candidate(from: "https://example.com/feed.xml"), "https://example.com/feed.xml")
        XCTAssertEqual(PasteboardFeedSuggestion.candidate(from: "http://example.com/rss"), "http://example.com/rss")
    }

    func testSchemeLessHostsPassThroughForDiscoveryToNormalise() {
        XCTAssertEqual(PasteboardFeedSuggestion.candidate(from: "example.com/feed.xml"), "example.com/feed.xml")
        XCTAssertEqual(PasteboardFeedSuggestion.candidate(from: "example.com"), "example.com")
    }

    func testSurroundingWhitespaceIsTrimmed() {
        XCTAssertEqual(PasteboardFeedSuggestion.candidate(from: "  https://example.com/rss\n"), "https://example.com/rss")
    }

    func testProseAndEmptyValuesAreRejected() {
        XCTAssertNil(PasteboardFeedSuggestion.candidate(from: ""))
        XCTAssertNil(PasteboardFeedSuggestion.candidate(from: "   \n"))
        XCTAssertNil(PasteboardFeedSuggestion.candidate(from: "read this example.com later"))
        XCTAssertNil(PasteboardFeedSuggestion.candidate(from: "r/apple"))
    }

    private func makePasteboard() -> NSPasteboard {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("PrecisTests.\(UUID().uuidString)"))
        pasteboard.clearContents()
        return pasteboard
    }
}

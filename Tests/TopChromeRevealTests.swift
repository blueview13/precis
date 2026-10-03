import AppKit
import XCTest
@testable import Precis

@MainActor
final class TopChromeRevealTests: XCTestCase {
    private let windowedMask: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .resizable]

    func testWindowedWindowContributesNoTitlebarHeight() {
        XCTAssertEqual(TopChromeReveal.revealedTitlebarHeight(for: windowedMask), 0)
        XCTAssertEqual(TopChromeReveal.revealedTitlebarHeight(for: .borderless), 0)
    }

    func testFullScreenTitlebarHeightMatchesTheSystemTitlebarMetric() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 200),
            styleMask: windowedMask,
            backing: .buffered,
            defer: false
        )
        let systemTitlebarHeight = window.frame.height - window.contentLayoutRect.height
        XCTAssertGreaterThan(systemTitlebarHeight, 0)

        XCTAssertEqual(TopChromeReveal.revealedTitlebarHeight(for: windowedMask.union(.fullScreen)), systemTitlebarHeight)
        // A content-under-titlebar window still slides the same strip down.
        XCTAssertEqual(
            TopChromeReveal.revealedTitlebarHeight(for: windowedMask.union([.fullScreen, .fullSizeContentView])),
            systemTitlebarHeight
        )
    }

    func testShiftStaysZeroWhileChromeIsHidden() {
        XCTAssertEqual(
            TopChromeReveal.contentShift(isChromeRevealed: false, menuBarHeight: 31, titlebarHeight: 32),
            0
        )
    }

    func testShiftClearsTheTitlebarAndMenuBarTogether() {
        let titlebarHeight = TopChromeReveal.revealedTitlebarHeight(for: windowedMask.union(.fullScreen))
        let menuBarHeight: CGFloat = 31
        let shift = TopChromeReveal.contentShift(
            isChromeRevealed: true,
            menuBarHeight: menuBarHeight,
            titlebarHeight: titlebarHeight
        )

        XCTAssertEqual(TopChromeReveal.revealedHeight(menuBarHeight: menuBarHeight, titlebarHeight: titlebarHeight), menuBarHeight + titlebarHeight)
        // Covering only the menu bar — the old behaviour — left the traffic
        // lights sitting on the content's top row.
        XCTAssertGreaterThan(shift, menuBarHeight + TopChromeReveal.clearance)
        XCTAssertGreaterThanOrEqual(shift, TopChromeReveal.revealedHeight(menuBarHeight: menuBarHeight, titlebarHeight: titlebarHeight))
    }
}

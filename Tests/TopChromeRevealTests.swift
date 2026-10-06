import AppKit
import XCTest
@testable import Precis

@MainActor
final class TopChromeRevealTests: XCTestCase {
    private let windowedMask: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .resizable]

    /// The system's titlebar metric, measured the way AppKit reports it.
    private func systemTitlebarHeight() -> CGFloat {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 200),
            styleMask: windowedMask,
            backing: .buffered,
            defer: false
        )
        let height = window.frame.height - window.contentLayoutRect.height
        XCTAssertGreaterThan(height, 0)
        return height
    }

    /// With the chrome away the strip only carries the first header row clear
    /// of the traffic lights: enough that they don't sit on it, and no more —
    /// sizing it for the revealed chrome here is what opened the band of empty
    /// space above the row while the menu bar was hidden.
    func testRestingInsetLeavesATightGapUnderTheLights() {
        let gap = TopChromeReveal.restingInset + PrecisSpacing.md - TopChromeReveal.trafficLightsBottomInset
        XCTAssertGreaterThan(gap, 0)
        XCTAssertLessThanOrEqual(gap, 20)
    }

    /// Revealed, the menu bar slides the window's titlebar — and the lights in
    /// it — down by its own height, so the chrome's bottom edge is the menu bar
    /// plus the titlebar, and the first header row has to stay below that with
    /// the clearance. Checked against the menu bars the app has to cope with,
    /// including a notched display's taller one.
    func testRevealedInsetClearsTheRevealedChrome() {
        let titlebar = systemTitlebarHeight()
        for menuBar in [CGFloat(24), 30, 37] {
            let inset = TopChromeReveal.revealedInset(
                menuBarHeight: menuBar,
                titlebarHeight: titlebar
            )
            XCTAssertGreaterThanOrEqual(
                inset + PrecisSpacing.md,
                menuBar + titlebar + TopChromeReveal.revealedClearance
            )
            XCTAssertGreaterThanOrEqual(inset, TopChromeReveal.restingInset)
        }
    }

    /// The lights sit inside the titlebar, so their bottom edge can't be below
    /// it — a constant that says otherwise describes a window AppKit doesn't
    /// build, and would overstate the clearance the header rows need.
    func testTrafficLightBottomSitsInsideTheTitlebar() {
        XCTAssertLessThanOrEqual(TopChromeReveal.trafficLightsBottomInset, systemTitlebarHeight())
    }

    /// The chrome is only treated as revealed when the pointer is at the top of
    /// the display *and* the window is flush with it — otherwise the menu bar is
    /// above the window, never on it, and hovering the window's top edge must
    /// not move the header rows.
    func testChromeCountsAsRevealedOnlyAtTheTopOfAFlushWindow() {
        XCTAssertTrue(
            TopChromeReveal.isChromeRevealed(pointerDistanceFromTop: 0, windowIsFlushWithTopOfDisplay: true)
        )
        XCTAssertTrue(
            TopChromeReveal.isChromeRevealed(
                pointerDistanceFromTop: TopChromeReveal.revealTriggerDepth,
                windowIsFlushWithTopOfDisplay: true
            )
        )
        XCTAssertFalse(
            TopChromeReveal.isChromeRevealed(
                pointerDistanceFromTop: TopChromeReveal.revealTriggerDepth + 1,
                windowIsFlushWithTopOfDisplay: true
            )
        )
        XCTAssertFalse(
            TopChromeReveal.isChromeRevealed(pointerDistanceFromTop: 0, windowIsFlushWithTopOfDisplay: false)
        )
    }
}

import AppKit
import XCTest
@testable import Precis

@MainActor
final class TopChromeRevealTests: XCTestCase {
    private let windowedMask: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .resizable]

    /// A standard (non-notched) menu bar. The inset has to fit this plus the
    /// titlebar, because in full screen the menu bar slides the titlebar — and
    /// the traffic lights in it — down by its own height.
    private let standardMenuBarHeight: CGFloat = 24

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

    /// The strip is content-free in every mode, so it must be at least as tall
    /// as the chrome that can be drawn inside it: the titlebar the traffic
    /// lights sit in, plus the menu bar that pushes it down in full screen.
    /// Lowering the inset below that puts the lights on the header row when a
    /// full-screen titlebar is revealed.
    func testInsetFitsTheTitlebarAndTheMenuBarAboveIt() {
        XCTAssertGreaterThanOrEqual(TopChromeReveal.topContentInset, systemTitlebarHeight())
        XCTAssertGreaterThanOrEqual(
            TopChromeReveal.topContentInset,
            systemTitlebarHeight() + standardMenuBarHeight
        )
    }
}

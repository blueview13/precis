import AppKit

/// Geometry for the chrome macOS reveals at the top of the screen when the
/// pointer reaches the menu bar: the bar itself, plus — over a full-screen
/// window — the window's own titlebar with its red/amber/green buttons, which
/// AppKit slides down beneath the bar.
@MainActor
enum TopChromeReveal {
    /// Extra drop below the revealed chrome so the content clears its hover
    /// backdrop instead of butting up against it.
    static let clearance: CGFloat = 13

    /// Height of the titlebar that comes down with the menu bar for a window
    /// with this style mask. Only full-screen windows lose their titlebar to
    /// the content, so windowed windows contribute nothing; the height itself
    /// is asked of AppKit so it follows the system's titlebar metric rather
    /// than a hard-coded number.
    static func revealedTitlebarHeight(for styleMask: NSWindow.StyleMask) -> CGFloat {
        guard styleMask.contains(.fullScreen), styleMask.contains(.titled) else { return 0 }

        // `.fullSizeContentView` only lets content extend under the titlebar —
        // it does not shrink the strip, and it makes AppKit report no chrome,
        // so drop it along with the full-screen flag to measure the real thing.
        var probeMask = styleMask
        probeMask.remove(.fullScreen)
        probeMask.remove(.fullSizeContentView)
        probeMask.insert(.titled)

        let probe = NSRect(x: 0, y: 0, width: 100, height: 100)
        let frame = NSWindow.frameRect(forContentRect: probe, styleMask: probeMask)
        return max(0, frame.height - probe.height)
    }

    /// How far down the chrome reaches from the top of the screen.
    static func revealedHeight(menuBarHeight: CGFloat, titlebarHeight: CGFloat) -> CGFloat {
        menuBarHeight + titlebarHeight
    }

    /// Padding the window content needs to sit clear of the revealed chrome.
    static func contentShift(isChromeRevealed: Bool, menuBarHeight: CGFloat, titlebarHeight: CGFloat) -> CGFloat {
        guard isChromeRevealed else { return 0 }
        return revealedHeight(menuBarHeight: menuBarHeight, titlebarHeight: titlebarHeight) + clearance
    }
}

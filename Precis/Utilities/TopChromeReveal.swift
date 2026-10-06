import AppKit

/// Geometry for the strip the window gives up at the top so macOS can reveal
/// its chrome — the menu bar, and over a full-screen window the titlebar with
/// its red/amber/green buttons — without moving or covering the content.
@MainActor
enum TopChromeReveal {
    /// Strip kept above the content while the chrome is out of the way.
    ///
    /// Only the margin the header rows need to clear the traffic lights, not
    /// the lights' own depth — the header rows add their own `PrecisSpacing.md`
    /// top padding below this inset, and the two together leave the first row
    /// about 10pt under the lights.
    static let restingInset: CGFloat = 16

    /// How close to the window's top edge the pointer has to come before the
    /// strip starts to expand. The menu bar reveals at the very top of the
    /// display and, when the window is flush with it, that is the window's top
    /// edge too — so the strip grows as the chrome slides in, instead of after
    /// the chrome has already landed on the header rows.
    static let revealTriggerDepth: CGFloat = 4

    /// Margin left between the revealed chrome's bottom edge and the first
    /// header row.
    static let revealedClearance: CGFloat = 8

    /// Where the traffic lights' bottom edge lands, measured from the top of the
    /// window — the 12pt buttons are vertically centred in the window's titlebar
    /// (32pt under AppKit's current metrics).
    static let trafficLightsBottomInset: CGFloat = 22

    /// Strip needed while the auto-hidden chrome is revealed over the content.
    ///
    /// The menu bar reveals *over* the window's own titlebar and slides it —
    /// and the traffic lights in it — down by its own height, so the chrome's
    /// bottom edge sits `menuBarHeight + titlebarHeight` below the window's top
    /// and the header rows have to stay below that. The menu bar's height is
    /// passed in rather than assumed: a notched display's is taller.
    static func revealedInset(menuBarHeight: CGFloat, titlebarHeight: CGFloat) -> CGFloat {
        max(
            restingInset,
            menuBarHeight + titlebarHeight + revealedClearance - PrecisSpacing.md
        )
    }

    /// Whether the chrome is over the window's content: the pointer has reached
    /// the top of the display and the window is flush with it, which is the only
    /// way the auto-hidden menu bar can be drawn on the window rather than above
    /// it.
    static func isChromeRevealed(pointerDistanceFromTop: CGFloat, windowIsFlushWithTopOfDisplay: Bool) -> Bool {
        windowIsFlushWithTopOfDisplay && pointerDistanceFromTop <= revealTriggerDepth
    }
}

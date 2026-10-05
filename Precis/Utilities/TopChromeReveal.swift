import AppKit

/// Geometry for the strip the window gives up at the top so macOS can reveal
/// its chrome — the menu bar, and over a full-screen window the titlebar with
/// its red/amber/green buttons — without moving or covering the content.
@MainActor
enum TopChromeReveal {
    /// Constant distance from the top of the window to the top of the content.
    ///
    /// Deliberately constant, and deliberately not derived from the window's
    /// safe area: the header rows sit at this offset in every mode — windowed,
    /// full screen, chrome showing or hidden — so revealing the menu bar can't
    /// push them down. It replaces sliding the whole layout down by the
    /// revealed height, which moved the top bar and the headers under it on
    /// every reveal.
    ///
    /// Tall enough for the tallest chrome that can appear over the window: the
    /// standard ~28pt titlebar (where the traffic lights live) plus the ~24pt
    /// menu bar that slides it down in full screen, so the lights land inside
    /// this strip and never on the header. Raise it for a taller menu bar (a
    /// notched display) or a larger accessibility text size.
    static let topContentInset: CGFloat = 52
}

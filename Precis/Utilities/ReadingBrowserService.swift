import AppKit
import SwiftUI

struct ReadingBrowserOption: Identifiable, Hashable {
    let bundleIdentifier: String
    let name: String

    var id: String { bundleIdentifier }
}

@MainActor
enum ReadingBrowserService {
    static let preferenceKey = "readingBrowserBundleIdentifier"
    static let systemDefaultIdentifier = "__system_default__"
    static let inAppIdentifier = "__precis_in_app__"

    /// Representative URL used to query the system for applications registered to open web pages.
    private static let webURLProbe = URL(string: "https://example.com")!

    static var systemDefaultBrowser: ReadingBrowserOption? {
        guard let appURL = NSWorkspace.shared.urlForApplication(toOpen: webURLProbe),
              let bundleIdentifier = Bundle(url: appURL)?.bundleIdentifier,
              let name = appName(at: appURL) else {
            return nil
        }
        return ReadingBrowserOption(bundleIdentifier: bundleIdentifier, name: name)
    }

    static var installedBrowsers: [ReadingBrowserOption] {
        var seen = Set<String>()
        return NSWorkspace.shared.urlsForApplications(toOpen: webURLProbe)
            .compactMap { appURL -> ReadingBrowserOption? in
                guard let bundleIdentifier = Bundle(url: appURL)?.bundleIdentifier,
                      seen.insert(bundleIdentifier).inserted,
                      let name = appName(at: appURL) else {
                    return nil
                }
                return ReadingBrowserOption(bundleIdentifier: bundleIdentifier, name: name)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static func open(_ url: URL) {
        let identifier = UserDefaults.standard.string(forKey: preferenceKey)
        if identifier == inAppIdentifier {
            PrecisBrowserWindowController.shared.open(url)
            return
        }
        if let identifier,
           identifier != systemDefaultIdentifier,
           let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier) {
            NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: NSWorkspace.OpenConfiguration())
        } else {
            NSWorkspace.shared.open(url)
        }
    }

    private static func appName(at url: URL) -> String? {
        guard let bundle = Bundle(url: url) else { return nil }
        return (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
    }
}

@MainActor
private final class PrecisBrowserWindowController: NSObject, NSWindowDelegate {
    static let shared = PrecisBrowserWindowController()
    private var windows: [NSWindow] = []

    func open(_ url: URL) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1000, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = url.host ?? "Precis Browser"
        window.delegate = self
        window.contentViewController = NSHostingController(rootView: BrowserView(url: url))
        window.center()
        windows.append(window)
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        windows.removeAll { $0 === window }
    }
}

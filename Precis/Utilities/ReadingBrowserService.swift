import AppKit

struct ReadingBrowserOption: Identifiable, Hashable {
    let bundleIdentifier: String
    let name: String

    var id: String { bundleIdentifier }
}

@MainActor
enum ReadingBrowserService {
    static let preferenceKey = "readingBrowserBundleIdentifier"
    static let systemDefaultIdentifier = "__system_default__"

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
        guard let identifier = UserDefaults.standard.string(forKey: preferenceKey),
              identifier != systemDefaultIdentifier,
              let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier) else {
            NSWorkspace.shared.open(url)
            return
        }
        NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: NSWorkspace.OpenConfiguration())
    }

    private static func appName(at url: URL) -> String? {
        guard let bundle = Bundle(url: url) else { return nil }
        return (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
    }
}

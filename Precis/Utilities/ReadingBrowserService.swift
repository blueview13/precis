import AppKit
import CoreServices

struct ReadingBrowserOption: Identifiable, Hashable {
    let bundleIdentifier: String
    let name: String

    var id: String { bundleIdentifier }
}

@MainActor
enum ReadingBrowserService {
    static let preferenceKey = "readingBrowserBundleIdentifier"
    static let systemDefaultIdentifier = "__system_default__"

    static var systemDefaultBrowser: ReadingBrowserOption? {
        guard let bundleIdentifier = LSCopyDefaultHandlerForURLScheme("https" as CFString)?.takeRetainedValue() as String?,
              let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier),
              let name = appName(at: appURL) else {
            return nil
        }
        return ReadingBrowserOption(bundleIdentifier: bundleIdentifier, name: name)
    }

    static var installedBrowsers: [ReadingBrowserOption] {
        let identifiers = (LSCopyAllHandlersForURLScheme("https" as CFString)?.takeRetainedValue() as? [String]) ?? []
        return identifiers.compactMap { identifier in
            guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier),
                  let name = appName(at: appURL) else {
                return nil
            }
            return ReadingBrowserOption(bundleIdentifier: identifier, name: name)
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

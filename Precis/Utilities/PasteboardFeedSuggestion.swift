import AppKit

/// The URL someone just copied, offered to the Add Feed sheet so it can open
/// pre-filled instead of waiting for a manual paste.
///
/// The value comes from the pasteboard's *detection* API rather than a raw
/// `string(forType:)` read: detection reports what is on the pasteboard without
/// handing over its contents, so macOS doesn't interrupt with the "Precis would
/// like to paste from …" alert every time the sheet opens.
enum PasteboardFeedSuggestion {
    /// Best guess at the URL on the general pasteboard, or `nil` when there is
    /// nothing URL-shaped to offer.
    static func copiedURL() async -> String? {
        await copiedURL(from: .general)
    }

    /// Reads one specific pasteboard — the general one in the app, a scratch
    /// one under test.
    static func copiedURL(from pasteboard: NSPasteboard) async -> String? {
        // The read itself is nonisolated, so keep the pasteboard off the main
        // actor rather than shipping a non-Sendable object across to it.
        let detected = try? await pasteboard.detectedValues(for: [\NSPasteboard.DetectedValues.probableWebURL])
        return detected.flatMap { candidate(from: $0.probableWebURL) }
    }

    /// A detected value that is worth putting in the Add Feed field. Detection
    /// matches more than web URLs — it happily reports `mailto:` and
    /// `javascript:` copies — so everything gets checked before it is offered.
    static func candidate(from detectedText: String) -> String? {
        let trimmed = detectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        // Feed intake is URL-driven, so interior whitespace (a copied sentence)
        // rules the value out.
        guard !trimmed.isEmpty, !trimmed.contains(where: \.isWhitespace) else { return nil }

        guard let components = URLComponents(string: trimmed) else { return nil }

        if let scheme = components.scheme?.lowercased() {
            guard scheme == "http" || scheme == "https", components.host?.isEmpty == false else { return nil }
            return trimmed
        }

        // A scheme-less copy ("example.com/feed.xml") is what feed discovery
        // normalises to https, so accept it when it reads as a bare host.
        let bareHost = trimmed.prefix { $0 != "/" && $0 != "?" && $0 != "#" }
        guard bareHost.contains("."), !trimmed.contains("@") else { return nil }
        guard let host = URLComponents(string: "https://\(trimmed)")?.host, !host.isEmpty else { return nil }
        return trimmed
    }
}

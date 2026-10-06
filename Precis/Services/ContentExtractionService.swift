import Foundation

public struct ExtractedArticleContent {
    public let title: String
    public let normalizedText: String
    public let excerpt: String
    public let wordCount: Int

    public init(title: String, normalizedText: String, excerpt: String, wordCount: Int) {
        self.title = title
        self.normalizedText = normalizedText
        self.excerpt = excerpt
        self.wordCount = wordCount
    }
}

public protocol ContentExtractionServiceProtocol {
    func extract(from rawText: String, title: String) -> ExtractedArticleContent
}

public final class ContentExtractionService: ContentExtractionServiceProtocol {
    public init() {}

    public func extract(from rawText: String, title: String) -> ExtractedArticleContent {
        let cleaned = rawText
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let excerpt = String(cleaned.prefix(260))
        let words = cleaned.split(whereSeparator: { $0.isWhitespace }).map(String.init)

        return ExtractedArticleContent(
            title: title,
            normalizedText: cleaned,
            excerpt: excerpt,
            wordCount: words.count
        )
    }
}

/// Fetches an article's web page and extracts the readable HTML fragment
/// (formatting + images intact) for the reading pane. Deliberately heuristic —
/// no external readability dependency — preferring `<article>`, then `<main>`,
/// then `<body>`, with page chrome (scripts, nav, footer…) stripped out.
public enum ArticleContentLoader {

    public enum LoaderError: Error, LocalizedError {
        case invalidResponse
        case emptyPage

        public var errorDescription: String? {
            switch self {
            case .invalidResponse: return "The article page could not be loaded."
            case .emptyPage: return "No readable content was found on the page."
            }
        }
    }

    /// Downloads `url` and returns a cleaned, URL-resolved HTML fragment.
    public static func fetchReadableHTML(from url: URL) async throws -> String {
        var request = URLRequest(url: url, timeoutInterval: 25)
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Precis/1.0",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw LoaderError.invalidResponse
        }

        let html = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1)
            ?? ""
        guard !html.isEmpty else { throw LoaderError.emptyPage }

        let fragment: String
        if let mercury = await MercuryArticleParser.parse(html: html, url: url),
           visibleTextLength(in: mercury.contentHTML) >= minimumArticleText {
            var readable = mercury.contentHTML
            if readable.range(of: #"<img\b"#, options: .regularExpression.union(.caseInsensitive)) == nil,
               let leadImageURL = mercury.leadImageURL {
                readable = addingLeadImage(leadImageURL, to: readable, base: url)
            }
            fragment = resolveURLs(in: readable, base: url)
        } else {
            // Keep Precis's existing heuristic as a compatibility fallback
            // for pages Mercury cannot parse or that return too little text.
            fragment = extractReadableHTML(from: html, base: url)
        }
        // Pages that render via JavaScript (Reddit, some paywalls) answer with
        // a near-empty shell — accepting it would overwrite the feed's own
        // content with nothing and leave the reading pane blank permanently.
        guard visibleTextLength(in: fragment) >= minimumArticleText else {
            throw LoaderError.emptyPage
        }
        return fragment
    }

    /// Mercury sometimes identifies a lead image without including it in the
    /// extracted body. Include that image when the body has no inline images
    /// so feeds that rely on the page's hero image keep their current display.
    private static func addingLeadImage(_ rawURL: String, to html: String, base: URL) -> String {
        guard let imageURL = URL(string: rawURL, relativeTo: base)?.absoluteURL,
              let scheme = imageURL.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else { return html }

        let escapedURL = imageURL.absoluteString
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
        return "<figure><img src=\"\(escapedURL)\" alt=\"\"></figure>\(html)"
    }

    /// Extracted fragments shorter than this many visible characters count as
    /// a failed fetch — see the guard in `fetchReadableHTML`.
    public static let minimumArticleText = 200

    /// Visible characters in an HTML fragment — tags and collapsed
    /// whitespace don't count.
    public static func visibleTextLength(in fragment: String) -> Int {
        let stripped = fragment.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        let collapsed = stripped
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return collapsed.count
    }

    /// Picks the article body out of a full page and strips chrome.
    static func extractReadableHTML(from html: String, base: URL) -> String {
        var text = html

        // Comments first — an HTML comment can swallow the block regexes below.
        text = replacing(in: text, pattern: "<!--.*?-->", with: "")

        // Page chrome: content INSIDE these tags goes away with them.
        for tag in ["script", "style", "noscript", "template", "svg", "iframe", "nav", "footer", "aside", "form", "button"] {
            text = replacing(
                in: text,
                pattern: "<\(tag)\\b[^>]*>.*?</\(tag)\\s*>",
                with: ""
            )
            // Self-closing variants (<svg …/>, <iframe …/>).
            text = replacing(in: text, pattern: "<\(tag)\\b[^>]*/>", with: "")
        }

        // Prefer the semantic containers, then fall back to the whole body.
        var fragment = firstMatch(in: text, pattern: "<article\\b[^>]*>.*?</article\\s*>")
            ?? firstMatch(in: text, pattern: "<main\\b[^>]*>.*?</main\\s*>")
            ?? firstMatch(in: text, pattern: "<body\\b[^>]*>.*?</body\\s*>")
            ?? text

        // The reading pane shows the article's own headline above the body —
        // drop a leading <h1> so the title isn't rendered twice.
        fragment = droppingLeadingHeadline(from: fragment)

        // Relative image/link URLs only resolve against the page URL.
        fragment = resolveURLs(in: fragment, base: base)

        return fragment
    }

    /// Removes a headline that opens the fragment (an `<h1>` appearing before
    /// any paragraph, image or list) — the duplicate of the pane's title bar.
    private static func droppingLeadingHeadline(from fragment: String) -> String {
        let options: String.CompareOptions = [.regularExpression, .caseInsensitive]
        guard let h1Start = fragment.range(of: "<h1\\b", options: options) else { return fragment }
        // If body content already began before the h1, it isn't the article
        // headline — leave it alone.
        if let firstContent = fragment.range(of: "<(p|img|ul|ol|figure|blockquote)\\b", options: options),
           firstContent.lowerBound < h1Start.lowerBound {
            return fragment
        }
        guard let h1End = fragment.range(
            of: "</h1\\s*>",
            options: options,
            range: h1Start.lowerBound..<fragment.endIndex
        ) else { return fragment }
        return String(fragment[..<h1Start.lowerBound]) + String(fragment[h1End.upperBound...])
    }

    // MARK: - Helpers

    private static func replacing(in text: String, pattern: String, with replacement: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else { return text }
        return regex.stringByReplacingMatches(
            in: text,
            range: NSRange(text.startIndex..., in: text),
            withTemplate: replacement
        )
    }

    private static func firstMatch(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else { return nil }
        guard let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range, in: text) else { return nil }
        return String(text[range])
    }

    private static func firstCapture(in text: String, pattern: String, group: Int = 1) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else { return nil }
        guard let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges > group,
              let range = Range(match.range(at: group), in: text) else { return nil }
        return String(text[range])
    }

    /// Resolves `src`/`href`/`poster`/`srcset` (and the common lazy-load
    /// `data-*` variants) against the page URL so images render inside the
    /// app instead of silently 404-ing on relative paths.
    public static func resolveURLs(in html: String, base: URL) -> String {
        var result = html

        // srcset lists: "url 1x, url2 2x" — resolve each candidate URL.
        result = transformMatches(in: result, pattern: "(srcset|data-srcset)\\s*=\\s*\"([^\"]*)\"") { match in
            let list = match[2]
            let resolved = list.components(separatedBy: ",").map { candidate -> String in
                let parts = candidate.trimmingCharacters(in: .whitespaces).split(separator: " ", maxSplits: 1)
                guard let first = parts.first, !first.isEmpty else { return candidate.trimmingCharacters(in: .whitespaces) }
                let url = resolve(String(first), base: base)
                let descriptor = parts.count > 1 ? " " + parts[1] : ""
                return url + descriptor
            }.joined(separator: ", ")
            return "\(match[1])=\"\(resolved)\""
        }

        // Plain attributes.
        result = transformMatches(in: result, pattern: "(src|href|poster|data-src|data-original)\\s*=\\s*\"([^\"]*)\"") { match in
            "\(match[1])=\"\(resolve(match[2], base: base))\""
        }
        result = transformMatches(in: result, pattern: "(src|href|poster|data-src|data-original)\\s*=\\s*'([^']*)'") { match in
            "\(match[1])='\(resolve(match[2], base: base))'"
        }

        // Lazy images: <img data-src="…" src=""> (or no src at all) — promote
        // the lazy URL into `src` so the web view actually loads it.
        result = transformMatches(in: result, pattern: "<img\\b[^>]*>") { groups in
            let tag = groups[0]
            let hasLazy = tag.range(of: "data-src=", options: .caseInsensitive) != nil
                || tag.range(of: "data-original=", options: .caseInsensitive) != nil
            guard hasLazy else { return tag }

            let lazy = firstCapture(in: tag, pattern: #"(?:data-src|data-original)\s*=\s*"([^"]*)""#)
                ?? firstCapture(in: tag, pattern: #"(?:data-src|data-original)\s*=\s*'([^']*)'"#)
            guard let lazy, !lazy.isEmpty else { return tag }

            let currentSrc = firstCapture(in: tag, pattern: #"\ssrc\s*=\s*"([^"]*)""#)
            if let currentSrc, !currentSrc.isEmpty { return tag } // real src already set
            if currentSrc != nil {
                // Empty src="" — fill it in place so no duplicate attribute.
                return tag.replacingOccurrences(of: "src=\"\"", with: "src=\"\(lazy)\"")
            }
            guard let close = tag.lastIndex(of: ">") else { return tag }
            return String(tag[..<close]) + " src=\"\(lazy)\">"
        }

        return result
    }

    private static func resolve(_ raw: String, base: URL) -> String {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return value }
        let lower = value.lowercased()
        // Already absolute, in-page, or a non-fetchable scheme — leave alone.
        if lower.hasPrefix("http://") || lower.hasPrefix("https://") || value.hasPrefix("//")
            || value.hasPrefix("#") || lower.hasPrefix("data:") || lower.hasPrefix("mailto:")
            || lower.hasPrefix("javascript:") || lower.hasPrefix("tel:") || lower.hasPrefix("blob:") {
            return value
        }
        guard let resolved = URL(string: value, relativeTo: base)?.absoluteURL,
              let scheme = resolved.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return value
        }
        return resolved.absoluteString
    }

    private static func transformMatches(
        in text: String,
        pattern: String,
        _ transform: ([String]) -> String
    ) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return text }
        let range = NSRange(text.startIndex..., in: text)
        var output = text
        // Collect first, then replace — mutating during enumeration shifts
        // the NSRange locations under the regex.
        let matches = regex.matches(in: text, range: range)
        for match in matches.reversed() {
            guard let swiftRange = Range(match.range, in: output) else { continue }
            let groups = (0..<match.numberOfRanges).map { index -> String in
                guard let r = Range(match.range(at: index), in: text) else { return "" }
                return String(text[r])
            }
            output.replaceSubrange(swiftRange, with: transform(groups))
        }
        return output
    }
}

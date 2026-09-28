import Foundation
import SwiftUI

/// Renders HTML content into SwiftUI `AttributedString` for rich article display.
enum HTMLAttributedStringRenderer {

    /// HTML parsing (`NSAttributedString.DocumentType.html`) round-trips through
    /// the system text agent and is expensive — cache the last few renders so a
    /// reading-pane re-render doesn't re-parse the same article on the main thread.
    private nonisolated(unsafe) static var cache: [String: AttributedString] = [:]
    private nonisolated(unsafe) static var cacheOrder: [String] = []
    private static let cacheLock = NSLock()
    // Sized for the font-size slider too: renders are cached per (size, html)
    // and a full drag touches up to 13 sizes of the same article.
    private static let cacheLimit = 24

    /// Attempt to render HTML into an `AttributedString`.
    /// Falls back to plain text if HTML parsing fails.
    ///
    /// Pass `size` to render the article at that body point size: every font
    /// in the parsed document is scaled relative to its dominant (body) size,
    /// so headings keep their hierarchy. Cached per (size, html) pair.
    static func render(_ html: String, size: CGFloat? = nil) -> AttributedString {
        let key = "\(size.map { String(Int($0)) } ?? "default")|\(html)"
        cacheLock.lock()
        if let hit = cache[key] {
            cacheLock.unlock()
            return hit
        }
        cacheLock.unlock()

        let rendered = renderUncached(html, size: size)

        cacheLock.lock()
        cache[key] = rendered
        cacheOrder.append(key)
        if cacheOrder.count > cacheLimit {
            let evicted = cacheOrder.removeFirst()
            cache[evicted] = nil
        }
        cacheLock.unlock()
        return rendered
    }

    private static func renderUncached(_ html: String, size: CGFloat?) -> AttributedString {
        guard let data = html.data(using: .utf8) else {
            return AttributedString(html)
        }

        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: NSAttributedString.DocumentType.html,
            .characterEncoding: String.Encoding.utf8.rawValue
        ]

        guard let parsed = try? NSAttributedString(data: data, options: options, documentAttributes: nil) else {
            return AttributedString(html)
        }

        guard let size else {
            return AttributedString(parsed)
        }

        return AttributedString(scalingFonts(in: parsed, to: size))
    }

    /// Resize every font in the parsed document so body copy lands on `size`.
    /// The dominant font size (by character count) is the body — scaling
    /// everything relative to it keeps h1/h2/bold proportional regardless of
    /// what point size the HTML importer chose as its base.
    private static func scalingFonts(in attributed: NSAttributedString, to size: CGFloat) -> NSAttributedString {
        var weights: [CGFloat: Int] = [:]
        attributed.enumerateAttribute(.font, in: NSRange(location: 0, length: attributed.length)) { value, range, _ in
            guard let font = value as? NSFont else { return }
            weights[font.pointSize, default: 0] += range.length
        }
        let bodySize = weights.max { $0.value < $1.value }?.key ?? 12
        let factor = size / bodySize

        let scaled = NSMutableAttributedString(attributedString: attributed)
        var updates: [(NSRange, NSFont)] = []
        attributed.enumerateAttribute(.font, in: NSRange(location: 0, length: attributed.length)) { value, range, _ in
            guard let font = value as? NSFont else { return }
            updates.append((range, NSFontManager.shared.convert(font, toSize: font.pointSize * factor)))
        }
        for (range, font) in updates {
            scaled.addAttribute(.font, value: font, range: range)
        }
        return scaled
    }

    /// Strip HTML tags and return plain text (used for snippets and fallback).
    static func plainText(from html: String) -> String {
        let htmlStripped = html
            .replacingOccurrences(of: "<br>", with: "\n")
            .replacingOccurrences(of: "<br/>", with: "\n")
            .replacingOccurrences(of: "<br />", with: "\n")
            .replacingOccurrences(of: "</p>", with: "\n")
            .replacingOccurrences(of: "</li>", with: "\n")
            .replacingOccurrences(of: "</div>", with: "\n")

        let withoutTags = htmlStripped
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")

        return withoutTags
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

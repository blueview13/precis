import Foundation
import SwiftUI

/// Renders HTML content into SwiftUI `AttributedString` for rich article display.
enum HTMLAttributedStringRenderer {

    /// Attempt to render HTML into an `AttributedString`.
    /// Falls back to plain text if HTML parsing fails.
    static func render(_ html: String) -> AttributedString {
        guard let data = html.data(using: .utf8) else {
            return AttributedString(html)
        }

        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: NSAttributedString.DocumentType.html,
            .characterEncoding: String.Encoding.utf8.rawValue
        ]

        guard let nsString = try? NSAttributedString(data: data, options: options, documentAttributes: nil) else {
            return AttributedString(html)
        }

        return AttributedString(nsString)
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

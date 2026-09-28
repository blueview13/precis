import Foundation
import SwiftData

public struct ArticleListItem: Identifiable, Hashable {
    public let id: UUID
    public var title: String
    public var feedTitle: String
    public var feedID: UUID?
    public var publishedDate: Date?
    public var isRead: Bool
    public var isStarred: Bool
    public var snippet: String
    public var link: String?
    public var imageURL: String?

    /// Estimated reading time in minutes based on article body word count.
    public var readingTimeMinutes: Int {
        let words = articleBody.split(separator: " ").count
        return max(1, words / 230)
    }

    /// Normalized plain text, computed once at init. The regex stripping below
    /// runs over the full article HTML — doing it per `body` render made the
    /// first sidebar interaction stall (spinning ball) while rows re-rendered.
    private var normalizedBody: String

    public var articleBody: String {
        normalizedBody.isEmpty ? title : normalizedBody
    }

    /// Original HTML content for rich rendering in the reading pane.
    public var rawArticleHTML: String {
        snippet.isEmpty ? title : snippet
    }

    /// Clean display text with HTML stripped.
    public var cleanSnippet: String {
        normalizedBody
    }

    public init(
        id: UUID = UUID(),
        title: String,
        feedTitle: String,
        publishedDate: Date? = nil,
        isRead: Bool = false,
        isStarred: Bool = false,
        snippet: String = "",
        link: String? = nil,
        imageURL: String? = nil
    ) {
        self.id = id
        self.title = title
        self.feedTitle = feedTitle
        self.publishedDate = publishedDate
        self.isRead = isRead
        self.isStarred = isStarred
        self.snippet = snippet
        self.link = link
        self.imageURL = imageURL
        self.normalizedBody = Self.normalizeArticleText(snippet)
    }

    public init(record: ArticleRecord) {
        self.id = record.id
        self.title = record.title
        self.feedTitle = record.feed?.title ?? "Inbox"
        self.feedID = record.feed?.id
        self.publishedDate = record.publishedDate ?? Date()
        self.isRead = record.isRead
        self.isStarred = record.isStarred
        let rawSnippet = record.extractedContentText ?? record.rawContentText ?? record.title
        self.snippet = rawSnippet
        self.link = record.link
        self.imageURL = record.imageURL
        // Reuse the persisted plain-text render when available — recomputing
        // it for every article on every load pegged the main thread at scale.
        self.normalizedBody = record.normalizedText ?? Self.normalizeArticleText(rawSnippet)
    }

    private static func normalizeArticleText(_ rawText: String) -> String {
        let htmlStripped = rawText
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
            .replacingOccurrences(of: "&rsquo;", with: "’")

        let decoded = decodeNumericEntities(withoutTags)

        let normalized = decoded
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return normalized
    }

    /// Decodes numeric HTML character references (`&#039;`, `&#8217;`, `&#x2019;`)
    /// so raw entity codes never leak into displayed text. Invalid codes are
    /// left as-is; scanning always advances, so the loop always terminates.
    private static func decodeNumericEntities(_ text: String) -> String {
        guard text.contains("&#") else { return text }

        var result = ""
        var remainder = Substring(text)
        while let open = remainder.range(of: "&#") {
            result += remainder[..<open.lowerBound]
            let afterOpen = remainder[open.upperBound...]
            if let close = afterOpen.firstIndex(of: ";") {
                let body = afterOpen[..<close]
                let isHex = body.first == "x" || body.first == "X"
                let digits = isHex ? String(body.dropFirst()) : String(body)
                if !digits.isEmpty,
                   let value = UInt32(digits, radix: isHex ? 16 : 10),
                   value != 0,
                   let scalar = Unicode.Scalar(value) {
                    result.append(Character(scalar))
                    remainder = remainder[afterOpen.index(after: close)...]
                    continue
                }
            }
            result += "&#"
            remainder = afterOpen
        }
        result += remainder
        return result
    }
}

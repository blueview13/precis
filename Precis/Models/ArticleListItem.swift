import Foundation
import SwiftData

public struct ArticleListItem: Identifiable, Hashable, Sendable {
    public let id: UUID
    public var title: String
    public var titleHash: String
    public var cleanURL: String?
    public var alsoIn: [String] = []
    public var feedTitle: String
    public var author: String?
    public var feedID: UUID?
    public var publishedDate: Date?
    public var isRead: Bool
    public var isStarred: Bool
    public var snippet: String
    public var link: String?
    public var imageURL: String?
    /// Raw HTML for the reading pane — feed-supplied markup or the full
    /// article fetched from `link`. Empty when only plain text is known.
    public var contentHTML: String

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
    /// Falls back to the plain snippet when no HTML has been stored yet.
    public var rawArticleHTML: String {
        if !contentHTML.isEmpty { return contentHTML }
        return snippet.isEmpty ? title : snippet
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
        imageURL: String? = nil,
        contentHTML: String = ""
    ) {
        self.id = id
        self.title = ArticleHTMLSanitizer.decodingHTMLEntities(title)
        self.titleHash = DeduplicationPipeline.titleHash(title)
        self.cleanURL = link.flatMap(URL.init(string:)).map(DeduplicationPipeline.canonicalURL)
        self.feedTitle = feedTitle
        self.author = nil
        self.publishedDate = publishedDate
        self.isRead = isRead
        self.isStarred = isStarred
        self.snippet = snippet
        self.link = link
        self.imageURL = imageURL
        self.contentHTML = contentHTML
        self.normalizedBody = Self.normalizeArticleText(snippet)
    }

    public init(record: ArticleRecord) {
        self.id = record.id
        self.title = ArticleHTMLSanitizer.decodingHTMLEntities(record.title)
        self.titleHash = record.titleHash ?? DeduplicationPipeline.titleHash(record.title)
        self.cleanURL = record.cleanURL ?? record.link.flatMap(URL.init(string:)).map(DeduplicationPipeline.canonicalURL)
        self.feedTitle = record.feed?.title ?? "Inbox"
        self.author = record.author
        self.feedID = record.feed?.id
        self.publishedDate = record.publishedDate ?? Date()
        self.isRead = record.isRead
        self.isStarred = record.isStarred
        let rawSnippet = record.extractedContentText ?? record.rawContentText ?? record.title
        self.snippet = rawSnippet
        self.link = record.link
        self.imageURL = record.imageURL
        self.contentHTML = record.contentHTMLText ?? ""
        // Reuse the persisted plain-text render when available — recomputing
        // it for every article on every load pegged the main thread at scale.
        // Whatever the source, the result is entity-decoded and has any
        // leading source-site chrome (category tags, duplicated headline,
        // byline | date, "N Comments", read time) cut off, so the list's
        // lead-in starts at the article text itself.
        let html = record.contentHTMLText ?? record.extractedContentText ?? record.rawContentText ?? ""
        if let stored = record.normalizedText, !stored.isEmpty {
            self.normalizedBody = Self.strippingLeadingMetadataBlob(
                ArticleHTMLSanitizer.decodingHTMLEntities(stored),
                title: record.title
            )
        } else if !html.isEmpty {
            self.normalizedBody = Self.strippingLeadingMetadataBlob(
                ArticleHTMLSanitizer.articlePlainText(from: html, title: record.title),
                title: record.title
            )
        } else {
            self.normalizedBody = Self.strippingLeadingMetadataBlob(
                Self.normalizeArticleText(rawSnippet),
                title: record.title
            )
        }
    }

    /// Marks the end of the source-site chrome that a flattened article
    /// render carries at its head. The cut runs to the LAST marker found in
    /// the opening stretch, dropping category tags, a duplicated headline, a
    /// byline | date, comment count and read time in one go.
    private static let metadataCutPatterns: [String] = [
        #"\b\d+\s+Comments?\b\s*"#,
        #"(?i)\b(?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]*\.?\s+\d{1,2},?\s+\d{4}\s*[-–—]?\s*\d{1,2}:\d{2}\s*(?:am|pm)?\s*[A-Z]{2,4}\b\s*"#,
        #"(?i)\b\d{1,2}:\d{2}\s*(?:am|pm)\s*(?:PT|ET|GMT|UTC|BST)\b\s*"#,
        #"(?i)\b\d+\s*min(?:ute)?s?\s+read\b\s*[•·]?\s*"#
    ]

    /// True when a persisted plain-text render still leads with source-site
    /// chrome, i.e. it was written before the lead was cleaned. The patterns
    /// mirror `metadataCutPatterns` so a flagged render is always fixable.
    static func looksLikeMetadataLead(_ text: String) -> Bool {
        let head = String(text.prefix(220))
        guard !head.isEmpty else { return false }
        if head.contains("&#") { return true }
        let patterns = [
            #"\b\d+\s+Comments?\b"#,
            #"(?i)\b\d+\s*min(?:ute)?s?\s+read\b"#,
            #"(?i)\b\d{1,2}:\d{2}\s*(?:am|pm)\s*(?:PT|ET|GMT|UTC|BST)\b"#,
            #"(?i)\b(?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]*\.?\s+\d{1,2},?\s+\d{4}\b"#
        ]
        for pattern in patterns where head.range(of: pattern, options: .regularExpression) != nil {
            return true
        }
        return false
    }

    /// Cuts source-site chrome off the head of a flattened article render so
    /// the row's lead-in shows the article text, not its metadata.
    private static func strippingLeadingMetadataBlob(_ text: String, title: String?) -> String {
        var working = text

        // A duplicated headline sitting at the very start.
        if let title, title.count > 12, working.count > title.count + 4,
           working.lowercased().hasPrefix(title.lowercased()) {
            working = String(working.dropFirst(title.count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let ns = working as NSString
        let limit = min(ns.length, 400)
        var cut: Int?
        for pattern in metadataCutPatterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            guard let match = regex.firstMatch(
                in: working,
                range: NSRange(location: 0, length: limit)
            ) else { continue }
            let end = match.range.location + match.range.length
            if cut == nil || end > cut! { cut = end }
        }
        guard let cut, cut > 0, cut < ns.length else { return working }
        return ns.substring(from: cut).trimmingCharacters(in: .whitespacesAndNewlines)
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

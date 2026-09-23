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

    public var articleBody: String {
        let normalized = Self.normalizeArticleText(snippet)
        return normalized.isEmpty ? title : normalized
    }

    /// Original HTML content for rich rendering in the reading pane.
    public var rawArticleHTML: String {
        snippet.isEmpty ? title : snippet
    }

    /// Clean display text with HTML stripped.
    public var cleanSnippet: String {
        Self.normalizeArticleText(snippet)
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
    }

    public init(record: ArticleRecord) {
        self.id = record.id
        self.title = record.title
        self.feedTitle = record.feed?.title ?? "Inbox"
        self.feedID = record.feed?.id
        self.publishedDate = record.publishedDate ?? Date()
        self.isRead = record.isRead
        self.isStarred = record.isStarred
        self.snippet = record.extractedContentText ?? record.rawContentText ?? record.title
        self.link = record.link
        self.imageURL = record.imageURL
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

        let normalized = withoutTags
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return normalized
    }
}

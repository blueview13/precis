import Foundation
import FeedKit

public enum FeedParsingError: Error, LocalizedError {
    case unsupportedFormat
    case parseFailure
    case emptyFeed

    public var errorDescription: String? {
        switch self {
        case .unsupportedFormat:
            return "The feed format is not supported."
        case .parseFailure:
            return "The feed could not be parsed."
        case .emptyFeed:
            return "The feed did not contain any readable entries."
        }
    }
}

public struct ParsedFeedEntry: Sendable {
    public let title: String
    public let author: String?
    public let publishedDate: Date?
    public let link: URL?
    public let content: String?
    public let imageURL: URL?

    public init(
        title: String,
        author: String? = nil,
        publishedDate: Date? = nil,
        link: URL? = nil,
        content: String? = nil,
        imageURL: URL? = nil
    ) {
        self.title = title
        self.author = author
        self.publishedDate = publishedDate
        self.link = link
        self.imageURL = imageURL
        // Clean HTML content: decode entities and strip tags
        self.content = content.map { Self.cleanHTML($0) }
    }

    /// Strip HTML tags and decode entities from content.
    private static func cleanHTML(_ html: String) -> String {
        var text = html
        // Remove HTML comments
        text = text.replacingOccurrences(of: "<!--[^>]*-->", with: "", options: .regularExpression)
        // Convert block elements to newlines
        text = text.replacingOccurrences(of: "<br\\s*/?>", with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: "</p>", with: "\n\n", options: .regularExpression)
        text = text.replacingOccurrences(of: "</div>", with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: "</li>", with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: "</tr>", with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: "</td>", with: " ", options: .regularExpression)
        // Strip all remaining HTML tags
        text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        // Decode common HTML entities
        text = text.replacingOccurrences(of: "&amp;", with: "&")
        text = text.replacingOccurrences(of: "&lt;", with: "<")
        text = text.replacingOccurrences(of: "&gt;", with: ">")
        text = text.replacingOccurrences(of: "&quot;", with: "\"")
        text = text.replacingOccurrences(of: "&#39;", with: "'")
        text = text.replacingOccurrences(of: "&nbsp;", with: " ")
        // Collapse whitespace
        text = text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return text
    }
}

public struct ParsedFeedResult: Sendable {
    public let title: String
    public let url: URL
    public let entries: [ParsedFeedEntry]

    public init(title: String, url: URL, entries: [ParsedFeedEntry]) {
        self.title = title
        self.url = url
        self.entries = entries
    }
}

public protocol FeedParserServiceProtocol: Sendable {
    func parse(data: Data, url: URL) async throws -> ParsedFeedResult
}

public final class FeedParserService: FeedParserServiceProtocol {
    public init() {}

    public func parse(data: Data, url: URL) async throws -> ParsedFeedResult {
        let parser = FeedParser(data: data)
        let result = parser.parse()

        switch result {
        case .success(let feed):
            return try normalize(feed: feed, url: url)
        case .failure:
            throw FeedParsingError.parseFailure
        }
    }

    private func normalize(feed: FeedKit.Feed, url: URL) throws -> ParsedFeedResult {
        switch feed {
        case .rss(let rssFeed):
            return ParsedFeedResult(
                title: rssFeed.title ?? url.host ?? "RSS Feed",
                url: url,
                entries: (rssFeed.items ?? []).compactMap { item -> ParsedFeedEntry? in
                    // Image priority: enclosure → media:thumbnail → <img> in HTML
                    let enclosureRaw = item.enclosure?.attributes?.url
                    let enclosureImage = enclosureRaw.flatMap { Self.resolveURL($0, base: url) }
                    let mediaImage = item.media?.mediaThumbnails?.first?.attributes?.url.flatMap { Self.resolveURL($0, base: url) }
                    let htmlImage = Self.extractFirstImage(from: item.description ?? "")

                    return ParsedFeedEntry(
                        title: item.title ?? "Untitled",
                        author: item.author,
                        publishedDate: item.pubDate,
                        link: item.link.flatMap(URL.init(string:)),
                        content: item.description,
                        imageURL: enclosureImage ?? mediaImage ?? htmlImage
                    )
                }
            )

        case .atom(let atomFeed):
            let entries = (atomFeed.entries ?? []).compactMap { entry -> ParsedFeedEntry? in
                // Try content → summary → media:description
                let content = entry.content?.value
                    ?? entry.summary?.value
                    ?? entry.media?.mediaDescription?.value
                    ?? ""
                let title = entry.title ?? "Untitled"
                let mediaThumb = entry.media?.mediaThumbnails?.first?.attributes?.url
                let imageURL = entry.links?.first(where: { $0.attributes?.type?.contains("image") == true })?.attributes?.href.flatMap(URL.init(string:))
                    ?? mediaThumb.flatMap(URL.init(string:))

                return ParsedFeedEntry(
                    title: title,
                    author: entry.authors?.first?.name,
                    publishedDate: entry.published ?? entry.updated,
                    link: entry.links?.first?.attributes?.href.flatMap(URL.init(string:)),
                    content: content,
                    imageURL: imageURL
                )
            }
            return ParsedFeedResult(
                title: atomFeed.title ?? url.host ?? "Atom Feed",
                url: url,
                entries: entries
            )

        case .json(let jsonFeed):
            return ParsedFeedResult(
                title: jsonFeed.title ?? url.host ?? "JSON Feed",
                url: url,
                entries: (jsonFeed.items ?? []).compactMap { item in
                    ParsedFeedEntry(
                        title: item.title ?? "Untitled",
                        author: item.author?.name,
                        publishedDate: item.datePublished,
                        link: item.url.flatMap(URL.init(string:)),
                        content: item.contentText ?? item.contentHtml,
                        imageURL: item.image.flatMap(URL.init(string:))
                    )
                }
            )

        @unknown default:
            throw FeedParsingError.unsupportedFormat
        }
    }

    /// Extract the first image URL from HTML content (e.g. from <img> tags).
    private static func extractFirstImage(from html: String) -> URL? {
        // Match <img src="..."> tags
        let pattern = #"<img[^>]+src=["']([^"']+)["']"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let range = Range(match.range(at: 1), in: html) else {
            return nil
        }
        let urlString = String(html[range])
        return URL(string: urlString)
    }

    /// Resolve a URL string against a base URL, handling relative paths.
    private static func resolveURL(_ urlString: String, base: URL) -> URL? {
        // If the string has a scheme (http/https), it's already absolute
        if urlString.hasPrefix("http://") || urlString.hasPrefix("https://") {
            return URL(string: urlString)
        }
        // Relative or schemeless — resolve against feed base URL
        return URL(string: urlString, relativeTo: base)?.absoluteURL
    }
}

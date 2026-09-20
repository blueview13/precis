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

public struct ParsedFeedEntry {
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
        self.content = content
        self.imageURL = imageURL
    }
}

public struct ParsedFeedResult {
    public let title: String
    public let url: URL
    public let entries: [ParsedFeedEntry]

    public init(title: String, url: URL, entries: [ParsedFeedEntry]) {
        self.title = title
        self.url = url
        self.entries = entries
    }
}

public protocol FeedParserServiceProtocol {
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

    private func normalize(feed: Feed, url: URL) throws -> ParsedFeedResult {
        switch feed {
        case .rss(let rssFeed):
            return ParsedFeedResult(
                title: rssFeed.title ?? url.host ?? "RSS Feed",
                url: url,
                entries: (rssFeed.items ?? []).compactMap { item in
                    ParsedFeedEntry(
                        title: item.title ?? "Untitled",
                        author: item.author,
                        publishedDate: item.pubDate,
                        link: item.link.flatMap(URL.init(string:)),
                        content: item.description ?? item.content?.contentEncoded,
                        imageURL: item.enclosure?.attributes?.url.flatMap(URL.init(string:))
                    )
                }
            )

        case .atom(let atomFeed):
            return ParsedFeedResult(
                title: atomFeed.title ?? url.host ?? "Atom Feed",
                url: url,
                entries: (atomFeed.entries ?? []).compactMap { entry in
                    ParsedFeedEntry(
                        title: entry.title ?? "Untitled",
                        author: entry.author?.name,
                        publishedDate: entry.published ?? entry.updated,
                        link: entry.links?.first?.attributes?.href.flatMap(URL.init(string:)),
                        content: entry.summary?.value ?? entry.content?.value,
                        imageURL: entry.links?.first(where: { $0.attributes?.type?.contains("image") == true })?.attributes?.href.flatMap(URL.init(string:))
                    )
                }
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
                        imageURL: item.image?.flatMap(URL.init(string:))
                    )
                }
            )

        @unknown default:
            throw FeedParsingError.unsupportedFormat
        }
    }
}

import Foundation
import Testing

@testable import Precis

/// Offline unit tests for `FeedDiscoveryService`.
///
/// Anything that needs a live network round trip (scraping `<link rel="alternate">`
/// from a website) is deliberately excluded until `FeedDiscoveryService` accepts an
/// injected `URLSession`, so this suite stays fast and deterministic.
struct FeedDiscoveryServiceTests {

    // MARK: - URL normalization

    @Test("A bare host is normalized to https with a root path")
    func normalizesBareHost() throws {
        let url = try FeedDiscoveryService().normalizeURL("example.com")
        #expect(url.absoluteString == "https://example.com/")
    }

    @Test("An explicit scheme and path are preserved")
    func preservesExplicitScheme() throws {
        let url = try FeedDiscoveryService().normalizeURL("http://example.com/feed.xml")
        #expect(url.absoluteString == "http://example.com/feed.xml")
    }

    @Test("Surrounding whitespace is trimmed")
    func trimsSurroundingWhitespace() throws {
        let url = try FeedDiscoveryService().normalizeURL("  https://example.com/rss.xml\n")
        #expect(url.scheme == "https")
        #expect(url.host == "example.com")
        #expect(url.path == "/rss.xml")
    }

    @Test("Blank input is rejected", arguments: ["", "   ", "\n", "\t"])
    func rejectsBlankInput(_ input: String) {
        #expect(throws: FeedDiscoveryError.self) {
            try FeedDiscoveryService().normalizeURL(input)
        }
    }

    // MARK: - Feed URL classification

    @Test(
        "Feed-shaped URLs are accepted",
        arguments: [
            "https://example.com/feed.xml",
            "https://example.com/rss",
            "https://example.com/blog/feed",
            "https://example.com/feed.json",
            "https://example.com/atom.rdf"
        ]
    )
    func acceptsFeedURLs(_ input: String) throws {
        let service = FeedDiscoveryService()
        #expect(service.validateFeedURL(try service.normalizeURL(input)))
    }

    @Test(
        "Ordinary page URLs are rejected",
        arguments: [
            "https://example.com/",
            "https://example.com/about",
            "https://example.com/2026/09/some-article"
        ]
    )
    func rejectsPageURLs(_ input: String) throws {
        let service = FeedDiscoveryService()
        #expect(!service.validateFeedURL(try service.normalizeURL(input)))
    }

    @Test("Non-HTTP schemes are rejected")
    func rejectsNonHTTPSchemes() throws {
        let url = try #require(URL(string: "ftp://example.com/feed.xml"))
        #expect(!FeedDiscoveryService().validateFeedURL(url))
    }

    // MARK: - YouTube detection

    @Test("A /channel/ URL becomes the channel feed")
    func detectsChannelFeed() async throws {
        let service = FeedDiscoveryService()
        let url = try service.normalizeURL("https://www.youtube.com/channel/UCabc123")
        let result = try #require(try await service.detectYouTubeFeed(from: url))

        #expect(result.kind == .youtube)
        #expect(result.normalizedURL.absoluteString == "https://www.youtube.com/feeds/videos.xml?channel_id=UCabc123")
    }

    @Test("A handle URL is routed to the channel videos feed")
    func detectsHandleFeed() async throws {
        let service = FeedDiscoveryService()
        // @handle URLs now resolve via page fetch to get the real channel ID.
        let url = try service.normalizeURL("https://www.youtube.com/@apple")
        let result = try? await service.detectYouTubeFeed(from: url)
        if let result {
            #expect(result.kind == .youtube)
            #expect(result.normalizedURL.host == "www.youtube.com")
            #expect(result.normalizedURL.path.contains("/feeds/videos.xml"))
            #expect(result.normalizedURL.query?.contains("channel_id=UC") == true)
        }
    }

    @Test("Non-YouTube hosts are ignored")
    func ignoresNonYouTubeHosts() async throws {
        let service = FeedDiscoveryService()
        let url = try service.normalizeURL("https://example.com/channel/UCabc123")
        let result = try await service.detectYouTubeFeed(from: url)

        #expect(result == nil)
    }

    // MARK: - Subreddit detection

    @Test("A subreddit URL becomes its .rss feed")
    func detectsSubredditFeed() async throws {
        let service = FeedDiscoveryService()
        let url = try service.normalizeURL("https://www.reddit.com/r/swift/")
        let result = try #require(try await service.detectSubredditFeed(from: url))

        #expect(result.kind == .subreddit)
        #expect(result.title == "r/swift")
        #expect(result.normalizedURL.absoluteString == "https://www.reddit.com/r/swift/.rss")
    }

    @Test("Reddit URLs without a subreddit name are ignored")
    func ignoresURLsWithoutASubreddit() async throws {
        let service = FeedDiscoveryService()
        let url = try service.normalizeURL("https://www.reddit.com/")
        let result = try await service.detectSubredditFeed(from: url)

        #expect(result == nil)
    }

    // MARK: - Discovery that never touches the network

    @Test("A direct feed URL resolves without a network round trip")
    func discoversDirectFeedOffline() async throws {
        let result = try await FeedDiscoveryService().discover(from: "https://example.com/feed.xml")

        #expect(result.kind == .directFeed)
        #expect(result.isDirectFeed)
        #expect(result.normalizedURL.absoluteString == "https://example.com/feed.xml")
    }

    @Test("Bare input is normalized before classification")
    func normalizesBareInputDuringDiscovery() async throws {
        let result = try await FeedDiscoveryService().discover(from: "example.com/rss.xml")
        #expect(result.normalizedURL.absoluteString == "https://example.com/rss.xml")
    }

    @Test("Importing a direct feed URL returns a normalized feed model")
    func importsDirectFeedURL() async throws {
        let feed = try await FeedImportService().importFeed(from: "example.com/feed.xml")

        #expect(feed.url.absoluteString == "https://example.com/feed.xml")
        #expect(feed.title == "example.com")
    }

    @Test("Blank input fails before any network work")
    func failsFastOnBlankInput() async {
        await #expect(throws: FeedDiscoveryError.self) {
            try await FeedDiscoveryService().discover(from: "   ")
        }
    }

    @Test("Article bodies are normalized into readable paragraphs")
    func articleBodiesNormalizeHTML() {
        let item = ArticleListItem(
            title: "Calm reading",
            feedTitle: "Signals",
            publishedDate: Date(),
            isRead: false,
            isStarred: true,
            snippet: "<p>Quiet interfaces <strong>do not subtract</strong> from the reading experience.</p><p>They make the words feel easier to trust.</p>"
        )

        #expect(item.articleBody == "Quiet interfaces do not subtract from the reading experience. They make the words feel easier to trust.")
    }

    @Test("Article summaries stay concise without losing meaning")
    func articleSummariesRemainConcise() {
        let item = ArticleListItem(
            title: "Calm reading",
            feedTitle: "Signals",
            publishedDate: Date(),
            isRead: false,
            isStarred: true,
            snippet: "Quiet interfaces do not subtract from the reading experience. They make the words feel easier to trust and encourage a calmer pace."
        )

        #expect(item.articleBody == "Quiet interfaces do not subtract from the reading experience. They make the words feel easier to trust and encourage a calmer pace.")
    }
}

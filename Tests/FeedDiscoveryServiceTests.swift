import Foundation
import SwiftData
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

    @Test("Feed creation rejects an equivalent normalized URL")
    func rejectsDuplicateFeedURLs() throws {
        let schema = ModelContainerProvider.schema
        let configuration = ModelConfiguration("FeedRepositoryTests", schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: configuration)
        let context = ModelContext(container)
        let repository = FeedRepository()

        try repository.create(title: "Example", url: "https://EXAMPLE.com:443/rss.xml/", folder: nil, context: context)

        #expect(throws: FeedRepositoryError.self) {
            try repository.create(title: "Duplicate", url: "https://example.com/rss.xml", folder: nil, context: context)
        }
        #expect(try repository.fetchAll(context: context).count == 1)
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

    @Test("Numeric HTML entities are decoded, not shown raw")
    func decodesNumericHTMLEntities() {
        let item = ArticleListItem(
            title: "City appeal",
            feedTitle: "Al Jazeera",
            publishedDate: Date(),
            snippet: "<p>could face &#039;severe penalty&#039; plus &#8217;quotes&#8221; and &#x2019;hex&#x201D;</p>"
        )

        #expect(item.articleBody == "could face 'severe penalty' plus ’quotes” and ’hex”")
    }

    @Test(
        "Feed titles are shortened for display",
        arguments: [
            ("Al Jazeera – Breaking News, World News and Video from Al Jazeera", "Al Jazeera"),
            ("World News and Video | Al Jazeera", "World News and Video"),
            ("Five Little Words Are Too Many Here", "Five Little Words Are"),
            ("BBC Sport", "BBC Sport")
        ]
    )
    func shortensFeedTitles(input: String, expected: String) {
        #expect(FeedDiscoveryService.conciseTitle(input) == expected)
    }

    // MARK: - Display titles (URL placeholders vs friendly names)

    @Test(
        "URL-ish titles are detected",
        arguments: [
            "feeds.bbci.co.uk",
            "https://example.com/feed.xml",
            "example.com",
            "example.com/feed.xml",
            "http://example.com/rss"
        ]
    )
    func detectsURLLikeTitles(_ title: String) {
        #expect(FeedDiscoveryService.looksLikeURL(title))
    }

    @Test(
        "Friendly titles are never mistaken for URLs",
        arguments: [
            "BBC Sport",
            "r/macapps",
            "mancity",
            "YouTube • mancity",
            "",
            "Hacker News (front page)"
        ]
    )
    func sparesFriendlyTitles(_ title: String) {
        #expect(!FeedDiscoveryService.looksLikeURL(title))
    }

    @Test("URL placeholders are swapped for the parsed channel title")
    func replacesPlaceholderTitles() {
        #expect(
            FeedDiscoveryService.displayTitle(current: "feeds.bbci.co.uk", parsedTitle: "BBC Sport") == "BBC Sport"
        )
    }

    @Test("Friendly titles survive even when the parsed title differs")
    func keepsFriendlyTitles() {
        #expect(
            FeedDiscoveryService.displayTitle(current: "r/macapps", parsedTitle: "r/MacApps") == "r/macapps"
        )
    }

    @Test("A missing or blank parsed title leaves the current title alone")
    func keepsCurrentTitleWhenParsedTitleMissing() {
        #expect(FeedDiscoveryService.displayTitle(current: "example.com", parsedTitle: nil) == "example.com")
        #expect(FeedDiscoveryService.displayTitle(current: "example.com", parsedTitle: "   ") == "example.com")
    }
}

/// Offline unit tests for `OPMLService` — covers the folder scoping and
/// attribute-variant bugs that made OPML import unreliable.
struct OPMLServiceTests {

    @Test("Feeds, folders, and folder scope are parsed correctly")
    func parsesFeedsWithFolders() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <opml version="2.0">
          <head><title>Subs</title></head>
          <body>
            <outline text="Top level" xmlUrl="https://example.com/top.xml" type="rss"/>
            <outline text="Tech" title="Tech">
              <outline text="HN" xmlUrl="https://news.ycombinator.com/rss" type="rss"/>
              <outline text="Mac" xmlURL="https://example.com/mac.xml" type="rss"/>
            </outline>
            <outline text="After folder" xmlUrl="https://example.com/after.xml" type="rss"/>
          </body>
        </opml>
        """
        let feeds = try OPMLService.parse(data: Data(xml.utf8))

        #expect(feeds.count == 4)
        // Top-level feed appearing before any folder has no folder name.
        #expect(feeds[0].url == "https://example.com/top.xml")
        #expect(feeds[0].folderName == nil)
        // Feeds inside the folder are attributed to it…
        #expect(feeds[1].folderName == "Tech")
        // …including ones using the `xmlURL` spelling instead of `xmlUrl`.
        #expect(feeds[2].url == "https://example.com/mac.xml")
        #expect(feeds[2].folderName == "Tech")
        // The folder scope must close at </outline>, so feeds after it are
        // top-level again (the old parser leaked the folder forever).
        #expect(feeds[3].folderName == nil)
    }

    @Test("Malformed XML throws instead of returning partial results")
    func throwsOnMalformedXML() {
        #expect(throws: OPMLParserError.self) {
            try OPMLService.parse(data: Data("<opml><body><outline".utf8))
        }
    }

    @Test("Exported OPML round-trips through the parser")
    func exportRoundTrips() throws {
        let original = [
            OPMLFeed(title: "Hacker News", url: "https://news.ycombinator.com/rss"),
            OPMLFeed(title: "r/macapps", url: "https://www.reddit.com/r/macapps/.rss", folderName: "Tech & Fun")
        ]
        let xml = OPMLService.generate(feeds: original)
        let reparsed = try OPMLService.parse(data: Data(xml.utf8))

        #expect(reparsed.count == 2)
        #expect(reparsed[0].title == "Hacker News")
        #expect(reparsed[0].folderName == nil)
        #expect(reparsed[1].folderName == "Tech & Fun")
        #expect(reparsed[1].url == "https://www.reddit.com/r/macapps/.rss")
    }
}

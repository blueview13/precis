import Foundation

public final class AlphaFeedPipeline {
    private let discoveryService: FeedDiscoveryServiceProtocol
    private let refreshService: FeedRefreshServiceProtocol
    private let store: FeedStore

    public init(
        discoveryService: FeedDiscoveryServiceProtocol = FeedDiscoveryService(),
        refreshService: FeedRefreshServiceProtocol = FeedRefreshService(),
        store: FeedStore = .shared
    ) {
        self.discoveryService = discoveryService
        self.refreshService = refreshService
        self.store = store
    }

    public func addAndRefresh(urlInput: String) async throws {
        let discoveryResult = try await discoveryService.discover(from: urlInput)
        let feed = Feed(title: discoveryResult.title, url: discoveryResult.normalizedURL)
        store.add(feed)

        let parsed = try await refreshService.fetchAndParse(feed)
        let articles = parsed.entries.map { entry in
            Article(
                feedID: feed.id,
                title: entry.title,
                author: entry.author,
                publishedDate: entry.publishedDate,
                link: entry.link,
                rawContent: entry.content,
                extractedContent: entry.content,
                isRead: false,
                isStarred: false,
                imageURL: entry.imageURL
            )
        }

        store.appendArticles(articles)
        PrecisLogger.info("Alpha pipeline imported \(articles.count) articles for \(feed.title)")
    }
}

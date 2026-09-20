import Foundation

public final class FeedStore: ObservableObject {
    // In-memory alpha store.
    nonisolated(unsafe) public static let shared = FeedStore()

    @Published public private(set) var feeds: [Feed] = []
    @Published public private(set) var articles: [Article] = []

    private init() {}

    public func add(_ feed: Feed) {
        guard !feeds.contains(where: { $0.url == feed.url }) else { return }
        feeds.append(feed)
    }

    public func replaceFeeds(with newFeeds: [Feed]) {
        feeds = newFeeds
    }

    public func appendArticles(_ newArticles: [Article]) {
        let existingKeys = Set(articles.map(\.id))
        let unique = newArticles.filter { !existingKeys.contains($0.id) }
        articles.append(contentsOf: unique)
    }
}

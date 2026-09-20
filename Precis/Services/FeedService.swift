import Foundation

public protocol FeedServiceProtocol {
    func refreshFeeds() async throws
    func addFeed(url: URL) async throws -> Feed
}

public final class FeedService: FeedServiceProtocol {
    public init() {}

    public func refreshFeeds() async throws {
        // Placeholder feed refresh pipeline.
    }

    public func addFeed(url: URL) async throws -> Feed {
        let feed = Feed(title: "New Feed", url: url)
        return feed
    }
}

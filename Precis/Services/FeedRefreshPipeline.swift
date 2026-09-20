import Foundation

public struct FeedRefreshSummary {
    public let feedID: UUID
    public let importedCount: Int
    public let updatedAt: Date

    public init(feedID: UUID, importedCount: Int, updatedAt: Date = Date()) {
        self.feedID = feedID
        self.importedCount = importedCount
        self.updatedAt = updatedAt
    }
}

public protocol FeedRefreshPipelineProtocol {
    func refresh(feed: Feed, existingArticles: [Article]) async throws -> FeedRefreshSummary
}

public final class FeedRefreshPipeline: FeedRefreshPipelineProtocol {
    private let fetcher: FeedRefreshServiceProtocol

    public init(fetcher: FeedRefreshServiceProtocol = FeedRefreshService()) {
        self.fetcher = fetcher
    }

    public func refresh(feed: Feed, existingArticles: [Article]) async throws -> FeedRefreshSummary {
        let parsed = try await fetcher.fetchAndParse(feed)
        let existingKeys = Set(existingArticles.map(\.title))
        let newArticles = parsed.entries.filter { !existingKeys.contains($0.title) }

        let importedCount = newArticles.count
        return FeedRefreshSummary(
            feedID: feed.id,
            importedCount: importedCount,
            updatedAt: Date()
        )
    }
}

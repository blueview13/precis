import Foundation

public final class FeedImportService {
    private let discoveryService: FeedDiscoveryServiceProtocol

    public init(discoveryService: FeedDiscoveryServiceProtocol = FeedDiscoveryService()) {
        self.discoveryService = discoveryService
    }

    public func importFeed(from rawInput: String) async throws -> Feed {
        let discoveryResult = try await discoveryService.discover(from: rawInput)
        let feed = Feed(
            title: discoveryResult.title,
            url: discoveryResult.normalizedURL
        )
        return feed
    }
}

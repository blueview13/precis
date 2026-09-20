import Foundation
import SwiftUI

@MainActor
public final class AlphaFeedViewModel: ObservableObject {
    @Published public var inputURL: String = ""
    @Published public var discoveredFeedTitle: String = ""
    @Published public var statusText: String = "Ready to add a feed"
    @Published public var isWorking: Bool = false
    @Published public var addedFeed: Feed?

    private let discoveryService: FeedDiscoveryServiceProtocol
    private let store: FeedStore

    public init(
        discoveryService: FeedDiscoveryServiceProtocol = FeedDiscoveryService(),
        store: FeedStore = .shared
    ) {
        self.discoveryService = discoveryService
        self.store = store
    }

    public func addFeed() async {
        guard !inputURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            statusText = "Please enter a feed URL or website URL."
            return
        }

        isWorking = true
        statusText = "Discovering feed..."

        do {
            let result = try await discoveryService.discover(from: inputURL)
            discoveredFeedTitle = result.title

            let feed = Feed(title: result.title, url: result.normalizedURL)
            store.add(feed)
            addedFeed = feed
            statusText = "Added feed: \(feed.title)"
        } catch {
            statusText = "Could not add feed: \(error.localizedDescription)"
        }

        isWorking = false
    }
}

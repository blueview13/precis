import Foundation

public enum FeedDiscoveryKind: String, Codable, Sendable {
    case directFeed
    case website
    case youtube
    case subreddit
}

public struct FeedDiscoveryResult: Sendable {
    public let originalInput: String
    public let normalizedURL: URL
    public let title: String
    public let kind: FeedDiscoveryKind
    public let isDirectFeed: Bool

    public init(
        originalInput: String,
        normalizedURL: URL,
        title: String,
        kind: FeedDiscoveryKind,
        isDirectFeed: Bool
    ) {
        self.originalInput = originalInput
        self.normalizedURL = normalizedURL
        self.title = title
        self.kind = kind
        self.isDirectFeed = isDirectFeed
    }
}

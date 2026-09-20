import Foundation

public protocol FeedRefreshServiceProtocol {
    func fetchAndParse(_ feed: Feed) async throws -> ParsedFeedResult
}

public final class FeedRefreshService: FeedRefreshServiceProtocol {
    private let parser: FeedParserServiceProtocol

    public init(parser: FeedParserServiceProtocol = FeedParserService()) {
        self.parser = parser
    }

    public func fetchAndParse(_ feed: Feed) async throws -> ParsedFeedResult {
        let request = URLRequest(url: feed.url, cachePolicy: .reloadRevalidatingCacheData, timeoutInterval: 20)
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw FeedParsingError.parseFailure
        }

        return try await parser.parse(data: data, url: feed.url)
    }
}

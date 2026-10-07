import Foundation

public protocol FeedRefreshServiceProtocol: Sendable {
    func fetchAndParse(_ feed: Feed) async throws -> ParsedFeedResult
}

public final class FeedRefreshService: FeedRefreshServiceProtocol {
    private let parser: FeedParserServiceProtocol
    private let session: URLSession

    public init(parser: FeedParserServiceProtocol = FeedParserService()) {
        self.parser = parser
        self.session = URLSession(
            configuration: .ephemeral,
            delegate: HTTPSRedirectDelegate(),
            delegateQueue: nil
        )
    }

    public func fetchAndParse(_ feed: Feed) async throws -> ParsedFeedResult {
        var request = URLRequest(url: feed.url, cachePolicy: .reloadRevalidatingCacheData, timeoutInterval: 20)
        // Set browser User-Agent to avoid 403 from sites like Reddit that block server requests
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15", forHTTPHeaderField: "User-Agent")
        // Signal we want XML/RSS content, not HTML
        request.setValue("application/rss+xml, application/xml, text/xml, */*", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw FeedParsingError.parseFailure
        }

        return try await parser.parse(data: data, url: feed.url)
    }
}

/// Some publishers redirect their HTTPS feed URL to an HTTP version of the
/// same URL. Upgrade that redirect before URLSession follows it, so App
/// Transport Security can keep HTTP disabled for the app.
private final class HTTPSRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        guard task.currentRequest?.url?.scheme?.lowercased() == "https",
              let url = request.url,
              url.scheme?.lowercased() == "http",
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            completionHandler(request)
            return
        }

        components.scheme = "https"
        var secureRequest = request
        secureRequest.url = components.url
        completionHandler(secureRequest.url == nil ? request : secureRequest)
    }
}

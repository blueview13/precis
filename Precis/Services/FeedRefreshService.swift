import Foundation
import SwiftData

public protocol FeedRefreshServiceProtocol: Sendable {
    func fetchAndParse(_ feed: Feed) async throws -> ParsedFeedResult
}

public final class FeedRefreshService: FeedRefreshServiceProtocol {
    private let parser: FeedParserServiceProtocol
    private static let session = URLSession(
        configuration: .ephemeral,
        delegate: HTTPSRedirectDelegate(),
        delegateQueue: nil
    )

    public init(parser: FeedParserServiceProtocol = FeedParserService()) {
        self.parser = parser
    }

    public func fetchAndParse(_ feed: Feed) async throws -> ParsedFeedResult {
        guard case .updated(let parsed, _) = try await fetch(feed.url, validators: nil) else {
            throw FeedParsingError.parseFailure
        }
        return parsed
    }

    struct Outcome {
        var newArticleCount = 0
        var titleChanged = false
        var libraryChanged: Bool { newArticleCount > 0 || titleChanged }
    }

    private struct Validators: Equatable {
        let requestURL: String
        let responseURL: String
        let etag: String?
        let lastModified: String?
    }

    private enum FetchResult {
        case unchanged
        case updated(ParsedFeedResult, Validators?)
    }

    @MainActor
    func refresh(_ feed: FeedRecord, context: ModelContext) async throws -> Outcome {
        guard let url = URL(string: feed.url) else { throw FeedParsingError.parseFailure }
        let feedID = feed.id
        let originalURL = feed.url
        let savedValidators: Validators?
        if let requestURL = feed.refreshRequestURL, let responseURL = feed.refreshResponseURL {
            savedValidators = Validators(requestURL: requestURL, responseURL: responseURL,
                                         etag: feed.refreshETag, lastModified: feed.refreshLastModified)
        } else {
            savedValidators = nil
        }
        guard case .updated(let parsed, let validators) = try await fetch(url, validators: savedValidators),
              !feed.isDeleted, feed.modelContext != nil, feed.url == originalURL else { return Outcome() }

        let count = try await ArticleIngestProcessor.shared.ingestParsed(parsed.entries, feedID: feedID, container: context.container)
        guard !feed.isDeleted, feed.modelContext != nil, feed.url == originalURL else {
            return Outcome(newArticleCount: count)
        }
        let title = FeedDiscoveryService.displayTitle(current: feed.title, parsedTitle: parsed.title)
        let outcome = Outcome(newArticleCount: count, titleChanged: title != feed.title)
        if outcome.libraryChanged || validators != savedValidators {
            let previousTitle = feed.title
            let previousDate = feed.lastFetched
            if outcome.titleChanged { feed.title = title }
            feed.lastFetched = Date()
            setValidators(validators, on: feed)
            do {
                try context.save()
            } catch {
                // Ingestion is already committed. Leave the validators eligible for
                // retry and still tell the caller about newly inserted articles.
                if outcome.titleChanged { feed.title = previousTitle }
                feed.lastFetched = previousDate
                setValidators(savedValidators, on: feed)
                if count == 0 { throw error }
                PrecisLogger.error("Could not save feed refresh metadata: \(error.localizedDescription)")
                return Outcome(newArticleCount: count)
            }
        }
        return outcome
    }

    @MainActor
    private func setValidators(_ validators: Validators?, on feed: FeedRecord) {
        feed.refreshRequestURL = validators?.requestURL
        feed.refreshResponseURL = validators?.responseURL
        feed.refreshETag = validators?.etag
        feed.refreshLastModified = validators?.lastModified
    }

    private func fetch(_ url: URL, validators: Validators?) async throws -> FetchResult {
        // Feed links still commonly use http:// even when the publisher also
        // serves the same endpoint over HTTPS. ATS blocks the former before a
        // request can reach the server, so try the secure equivalent first.
        let requestURL = Self.httpsEquivalent(of: url)
        var request = URLRequest(url: requestURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        // Set browser User-Agent to avoid 403 from sites like Reddit that block server requests
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15", forHTTPHeaderField: "User-Agent")
        // Signal we want XML/RSS content, not HTML
        request.setValue("application/rss+xml, application/xml, text/xml, */*", forHTTPHeaderField: "Accept")
        let conditional = validators?.requestURL == requestURL.absoluteString ? validators : nil
        if let conditional, conditional.responseURL == requestURL.absoluteString {
            request.setValue(conditional.etag, forHTTPHeaderField: "If-None-Match")
            request.setValue(conditional.lastModified, forHTTPHeaderField: "If-Modified-Since")
        }
        let (data, response) = try await Self.session.data(for: request, delegate: HTTPSRedirectDelegate(
            validatorURL: conditional?.responseURL, etag: conditional?.etag, lastModified: conditional?.lastModified
        ))

        guard let httpResponse = response as? HTTPURLResponse else { throw FeedParsingError.parseFailure }
        let responseURL = httpResponse.url ?? requestURL
        if httpResponse.statusCode == 304, let conditional,
           conditional.responseURL == responseURL.absoluteString {
            return .unchanged
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw FeedParsingError.parseFailure
        }

        let parsed = try await parser.parse(data: data, url: responseURL)
        let etag = httpResponse.value(forHTTPHeaderField: "ETag")
        let lastModified = httpResponse.value(forHTTPHeaderField: "Last-Modified")
        let updatedValidators = etag == nil && lastModified == nil ? nil : Validators(
            requestURL: requestURL.absoluteString, responseURL: responseURL.absoluteString,
            etag: etag, lastModified: lastModified
        )
        return .updated(parsed, updatedValidators)
    }

    private static func httpsEquivalent(of url: URL) -> URL {
        guard url.scheme?.lowercased() == "http",
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }
        components.scheme = "https"
        return components.url ?? url
    }
}

/// Some publishers redirect their HTTPS feed URL to an HTTP version of the
/// same URL. Upgrade that redirect before URLSession follows it, so App
/// Transport Security can keep HTTP disabled for the app.
private final class HTTPSRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    let validatorURL: String?
    let etag: String?
    let lastModified: String?

    init(validatorURL: String? = nil, etag: String? = nil, lastModified: String? = nil) {
        self.validatorURL = validatorURL
        self.etag = etag
        self.lastModified = lastModified
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        var redirected = request
        if task.currentRequest?.url?.scheme?.lowercased() == "https",
           let url = request.url, url.scheme?.lowercased() == "http",
           var components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            components.scheme = "https"
            redirected.url = components.url ?? url
        }
        let matches = validatorURL != nil && redirected.url?.absoluteString == validatorURL
        redirected.setValue(matches ? etag : nil, forHTTPHeaderField: "If-None-Match")
        redirected.setValue(matches ? lastModified : nil, forHTTPHeaderField: "If-Modified-Since")
        completionHandler(redirected)
    }
}

import Foundation

public enum FeedDiscoveryError: Error, LocalizedError {
    case invalidURL
    case unsupportedInput
    case noFeedFound

    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "The feed URL is invalid."
        case .unsupportedInput:
            return "The URL could not be recognized as a feed or supported website."
        case .noFeedFound:
            return "No valid feed URL was found for this website."
        }
    }
}

public protocol FeedDiscoveryServiceProtocol {
    func discover(from rawInput: String) async throws -> FeedDiscoveryResult
    func normalizeURL(_ rawInput: String) throws -> URL
    func validateFeedURL(_ url: URL) -> Bool
}

public final class FeedDiscoveryService: FeedDiscoveryServiceProtocol {
    public init() {}

    public func discover(from rawInput: String) async throws -> FeedDiscoveryResult {
        let normalizedURL = try normalizeURL(rawInput)

        if let direct = try validateAndClassifyDirectFeed(for: normalizedURL) {
            return direct
        }

        if let youtubeResult = try await detectYouTubeFeed(from: normalizedURL) {
            return youtubeResult
        }

        if let subredditResult = try await detectSubredditFeed(from: normalizedURL) {
            return subredditResult
        }

        if let websiteResult = try await detectWebsiteAlternateFeed(from: normalizedURL) {
            return websiteResult
        }

        throw FeedDiscoveryError.noFeedFound
    }

    public func normalizeURL(_ rawInput: String) throws -> URL {
        let trimmed = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw FeedDiscoveryError.invalidURL }

        let maybeURL: URL
        if let url = URL(string: trimmed), url.scheme != nil, url.host != nil {
            maybeURL = url
        } else if let url = URL(string: "https://\(trimmed)"), url.host != nil {
            maybeURL = url
        } else {
            throw FeedDiscoveryError.invalidURL
        }

        var components = URLComponents(url: maybeURL, resolvingAgainstBaseURL: false) ?? URLComponents()
        components.scheme = components.scheme ?? "https"
        components.host = components.host ?? maybeURL.host
        components.path = components.path.isEmpty ? "/" : components.path

        guard let fixedURL = components.url else {
            throw FeedDiscoveryError.invalidURL
        }

        return fixedURL
    }

    public func validateFeedURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme, ["http", "https"].contains(scheme), url.host != nil else {
            return false
        }

        let lowerPath = url.path.lowercased()
        let knownFeedSuffixes = [".rss", ".xml", ".atom", ".rdf", ".json"]

        return knownFeedSuffixes.contains { lowerPath.hasSuffix($0) }
            || lowerPath.contains("/feed")
            || lowerPath.contains("/feeds")
            || lowerPath.contains("rss")
            || lowerPath.contains("atom")
            || lowerPath.contains("jsonfeed")
    }

    private func validateAndClassifyDirectFeed(for url: URL) throws -> FeedDiscoveryResult? {
        guard validateFeedURL(url) else { return nil }

        let title = url.host ?? "Feed"
        return FeedDiscoveryResult(
            originalInput: url.absoluteString,
            normalizedURL: url,
            title: title,
            kind: .directFeed,
            isDirectFeed: true
        )
    }

    private func detectYouTubeFeed(from url: URL) async throws -> FeedDiscoveryResult? {
        let host = url.host?.lowercased() ?? ""
        guard host.contains("youtube.com") || host == "youtu.be" else { return nil }

        let path = url.path
        let channelID: String?

        if path.contains("/channel/") {
            channelID = path.components(separatedBy: "/channel/").last
        } else if path.contains("/user/") {
            channelID = path.components(separatedBy: "/user/").last
        } else if path.contains("/@") {
            channelID = path.components(separatedBy: "/@").last
        } else {
            channelID = nil
        }

        guard let channelID, !channelID.isEmpty else {
            return nil
        }

        let youtubeURL = URL(string: "https://www.youtube.com/feeds/videos.xml?channel_id=\(channelID)")
        guard let youtubeURL else { return nil }

        return FeedDiscoveryResult(
            originalInput: url.absoluteString,
            normalizedURL: youtubeURL,
            title: "YouTube • \(channelID)",
            kind: .youtube,
            isDirectFeed: true
        )
    }

    private func detectSubredditFeed(from url: URL) async throws -> FeedDiscoveryResult? {
        let host = url.host?.lowercased() ?? ""
        guard host.contains("reddit.com") else { return nil }

        let pathParts = url.path.split(separator: "/").map(String.init)
        guard pathParts.count >= 2, pathParts[0] == "r", !pathParts[1].isEmpty else { return nil }

        let subreddit = pathParts[1]
        let rssURL = URL(string: "https://www.reddit.com/r/\(subreddit)/.rss")
        guard let rssURL else { return nil }

        return FeedDiscoveryResult(
            originalInput: url.absoluteString,
            normalizedURL: rssURL,
            title: "r/\(subreddit)",
            kind: .subreddit,
            isDirectFeed: true
        )
    }

    private func detectWebsiteAlternateFeed(from url: URL) async throws -> FeedDiscoveryResult? {
        let html = try await fetchHTML(from: url)
        guard let feedURL = findAlternateFeedLink(in: html, baseURL: url) else { return nil }

        return FeedDiscoveryResult(
            originalInput: url.absoluteString,
            normalizedURL: feedURL,
            title: url.host ?? "Website Feed",
            kind: .website,
            isDirectFeed: true
        )
    }

    private func fetchHTML(from url: URL) async throws -> String {
        let request = URLRequest(url: url, cachePolicy: .reloadRevalidatingCacheData, timeoutInterval: 15)
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw FeedDiscoveryError.noFeedFound
        }

        guard let html = String(data: data, encoding: .utf8) else {
            throw FeedDiscoveryError.noFeedFound
        }

        return html
    }

    private func findAlternateFeedLink(in html: String, baseURL: URL) -> URL? {
        let pattern = "<link[^>]+rel=\"alternate\"[^>]+href=\"([^\"]+)\"|<link[^>]+href=\"([^\"]+)\"[^>]+rel=\"alternate\""
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return nil
        }

        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        let matches = regex.matches(in: html, options: [], range: range)

        for match in matches {
            if let hrefRange = Range(match.range(at: 1), in: html) {
                let href = String(html[hrefRange])
                if let feedURL = resolveRelativeURL(href, baseURL: baseURL) {
                    return feedURL
                }
            }
            if let hrefRange = Range(match.range(at: 2), in: html) {
                let href = String(html[hrefRange])
                if let feedURL = resolveRelativeURL(href, baseURL: baseURL) {
                    return feedURL
                }
            }
        }

        return nil
    }

    private func resolveRelativeURL(_ href: String, baseURL: URL) -> URL? {
        let cleaned = href.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }

        if let absoluteURL = URL(string: cleaned), absoluteURL.scheme != nil, absoluteURL.host != nil {
            return absoluteURL
        }

        if let relativeURL = URL(string: cleaned, relativeTo: baseURL) {
            return relativeURL
        }

        return nil
    }
}
